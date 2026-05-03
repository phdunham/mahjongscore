// TileCam — holds an AVCaptureSession open and streams frames to disk so the
// shell script pays warmup cost exactly once.
//
// Protocol (line-based on stdin; responses on stdout, flushed per line):
//
//   "ready device=<name>"                               — session hot
//
// Single shot:
//   stdin:  "capture <path>"                            (or bare "<path>" for back-compat)
//   stdout: "ok <path>"     | "err <message>"
//
// Burst (shell controls duration):
//   stdin:  "burst_start <startIdx> <prefix> <dir>"
//   stdout: "ok burst_started"
//   ...frames stream to <dir>/<prefix>_NNNN.jpeg...
//   stdin:  "burst_stop"
//   stdout: "ok burst count=<N> errors=<M> first=<i> last=<j>"
//
// Shutdown:
//   stdin:  "quit" or EOF
//
// Implementation note: AVCapturePhotoOutput hangs with Continuity Camera.
// We instead sample AVCaptureVideoDataOutput frames; on-demand JPEG encode
// via CIImage → CGImage → NSBitmapImageRep.

import AVFoundation
import AppKit
import CoreImage
import Foundation

// MARK: - I/O helpers

func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func emitErr(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

// MARK: - Device discovery

func discoverVideoDevices() -> [AVCaptureDevice] {
    let types: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .external,
        .continuityCamera,
        .deskViewCamera,
    ]
    return AVCaptureDevice.DiscoverySession(
        deviceTypes: types, mediaType: .video, position: .unspecified
    ).devices
}

// MARK: - Argument parsing

var requestedDevice: String? = nil
var listOnly = false
var targetFPS: Int = 0  // 0 = no rate limit; applies to burst mode only.
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--list":
            listOnly = true
        case "--device":
            guard let name = it.next() else {
                emitErr("err --device requires a value")
                exit(64)
            }
            requestedDevice = name
        case "--fps":
            guard let v = it.next(), let n = Int(v), n > 0 else {
                emitErr("err --fps requires a positive integer")
                exit(64)
            }
            targetFPS = n
        case "-h", "--help":
            print("""
            Usage: TileCam [--device NAME] [--fps N] [--list]
              --device NAME   use camera with exact localizedName NAME
              --fps N         cap burst frame rate to N fps (default: unlimited)
              --list          list video devices and exit
            """)
            exit(0)
        default:
            emitErr("err unknown argument: \(arg)")
            exit(64)
        }
    }
}

if listOnly {
    for d in discoverVideoDevices() {
        print(d.localizedName)
    }
    exit(0)
}

// MARK: - Runner

final class Runner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let sampleQueue = DispatchQueue(label: "tilecam.samples")
    let encodeQueue = DispatchQueue(label: "tilecam.encode", qos: .userInitiated)
    let ciContext = CIContext()

    // Latest frame for single-shot capture.
    private let bufferLock = NSLock()
    private var _latestBuffer: CVPixelBuffer?

    // Burst state.
    private let burstLock = NSLock()
    private var burstActive = false
    private var burstDir: URL?
    private var burstPrefix = ""
    private var burstNextIndex = 1
    private var burstFirstIndex = 1
    private var burstCount = 0
    private var burstErrors = 0
    // Rate limiting: 0 means accept every frame. Otherwise, skip any frame
    // that arrives within `burstMinInterval` seconds of the last accepted one.
    var burstMinInterval: Double = 0
    private var burstLastAccept: Double = 0

    func configure(deviceName: String?, fps: Int) throws {
        let devices = discoverVideoDevices()
        let device: AVCaptureDevice?
        if let name = deviceName {
            device = devices.first(where: { $0.localizedName == name })
            if device == nil {
                let names = devices.map { "\"\($0.localizedName)\"" }.joined(separator: ", ")
                throw RunnerError.noDevice("no device named \"\(name)\". available: \(names)")
            }
        } else {
            device = AVCaptureDevice.default(for: .video) ?? devices.first
            if device == nil {
                throw RunnerError.noDevice("no video capture devices found")
            }
        }
        let dev = device!

        session.beginConfiguration()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: dev)
        guard session.canAddInput(input) else {
            throw RunnerError.sessionSetup("cannot add input for \(dev.localizedName)")
        }
        session.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(videoOutput) else {
            throw RunnerError.sessionSetup("cannot add video output")
        }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        // Best-effort hardware rate cap. Some devices (notably Continuity
        // Camera) silently ignore this; the software decimator below is the
        // authoritative limiter.
        if fps > 0 {
            burstMinInterval = 1.0 / Double(fps)
            do {
                try dev.lockForConfiguration()
                let desired = CMTime(value: 1, timescale: CMTimeScale(fps))
                var supported = false
                for r in dev.activeFormat.videoSupportedFrameRateRanges {
                    if Double(fps) >= r.minFrameRate && Double(fps) <= r.maxFrameRate {
                        supported = true
                        break
                    }
                }
                if supported {
                    dev.activeVideoMinFrameDuration = desired
                    dev.activeVideoMaxFrameDuration = desired
                }
                dev.unlockForConfiguration()
            } catch {
                // Not fatal — software decimation still works.
            }
        }

        session.startRunning()

        // Block until the first frame arrives.
        let deadline = Date().addingTimeInterval(8)
        while currentBuffer() == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard currentBuffer() != nil else {
            throw RunnerError.sessionSetup("no frames received from \(dev.localizedName) within 8s")
        }

        emit("ready device=\(dev.localizedName)")
    }

    private func currentBuffer() -> CVPixelBuffer? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return _latestBuffer
    }

    // MARK: Single shot

    func capture(to path: String) -> String? {
        guard let buffer = currentBuffer() else {
            return "no frame available"
        }
        return encode(buffer: buffer, toPath: path)
    }

    private func encode(buffer: CVPixelBuffer, toPath path: String) -> String? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return "failed to create CGImage"
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(
            using: .jpeg, properties: [.compressionFactor: 0.9]
        ) else {
            return "jpeg encoding failed"
        }
        do {
            try jpeg.write(to: URL(fileURLWithPath: path))
            return nil
        } catch {
            return "write failed: \(error.localizedDescription)"
        }
    }

    // MARK: Burst

    func startBurst(dir: URL, prefix: String, startIndex: Int) {
        burstLock.lock()
        burstActive = true
        burstDir = dir
        burstPrefix = prefix
        burstFirstIndex = startIndex
        burstNextIndex = startIndex
        burstCount = 0
        burstErrors = 0
        burstLastAccept = 0  // accept the first incoming frame immediately
        burstLock.unlock()
    }

    /// Returns (count, errors, firstIndex, lastIndex). lastIndex is firstIndex-1
    /// when nothing was written.
    func stopBurst() -> (count: Int, errors: Int, first: Int, last: Int) {
        burstLock.lock()
        burstActive = false
        let result = (burstCount, burstErrors, burstFirstIndex, burstNextIndex - 1)
        burstLock.unlock()
        // Drain any encodes that are still in flight on encodeQueue so the
        // caller sees stable counts and all files on disk.
        encodeQueue.sync { }
        // Re-read — counts may have advanced while we drained.
        burstLock.lock()
        let final = (burstCount, burstErrors, burstFirstIndex, burstNextIndex - 1)
        burstLock.unlock()
        _ = result
        return final
    }

    // MARK: Sample buffer delegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        bufferLock.lock()
        _latestBuffer = pb
        bufferLock.unlock()

        // Snapshot burst state under the lock. Software-decimate here so
        // the accept/reject decision stays atomic with the index bump.
        let now = CFAbsoluteTimeGetCurrent()
        burstLock.lock()
        let active = burstActive
        let dir = burstDir
        let prefix = burstPrefix
        var accept = active && dir != nil
        if accept && burstMinInterval > 0 && burstLastAccept != 0 {
            if (now - burstLastAccept) < burstMinInterval {
                accept = false
            }
        }
        var idx = 0
        if accept {
            idx = burstNextIndex
            burstNextIndex += 1
            burstLastAccept = now
        }
        burstLock.unlock()

        guard accept, let dir = dir else { return }
        let filename = "\(prefix)_\(String(format: "%04d", idx)).jpeg"
        let url = dir.appendingPathComponent(filename)
        // Offload encode to keep the capture queue responsive. CVPixelBuffer
        // is reference-counted, so we retain it into the async block.
        encodeQueue.async { [weak self] in
            guard let self = self else { return }
            if let _ = self.encode(buffer: pb, toPath: url.path) {
                self.burstLock.lock()
                self.burstErrors += 1
                self.burstLock.unlock()
            } else {
                self.burstLock.lock()
                self.burstCount += 1
                self.burstLock.unlock()
            }
        }
    }

    enum RunnerError: Error, CustomStringConvertible {
        case noDevice(String)
        case sessionSetup(String)

        var description: String {
            switch self {
            case .noDevice(let m), .sessionSetup(let m): return m
            }
        }
    }
}

// MARK: - Main

let runner = Runner()
do {
    try runner.configure(deviceName: requestedDevice, fps: targetFPS)
} catch {
    emit("err \(error)")
    exit(2)
}

/// Splits "burst_start 5 1m /some/dir with spaces" → ["burst_start","5","1m","/some/dir with spaces"].
func splitCommand(_ line: String, expected: Int) -> [String] {
    var parts: [String] = []
    var remaining = Substring(line)
    for _ in 0..<(expected - 1) {
        if let sp = remaining.firstIndex(of: " ") {
            parts.append(String(remaining[..<sp]))
            remaining = remaining[remaining.index(after: sp)...]
        } else {
            parts.append(String(remaining))
            remaining = ""
        }
    }
    parts.append(String(remaining))
    return parts
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }
    if trimmed == "quit" { break }

    if trimmed.hasPrefix("capture ") {
        let path = String(trimmed.dropFirst("capture ".count))
        if let err = runner.capture(to: path) {
            emit("err \(err)")
        } else {
            emit("ok \(path)")
        }
    } else if trimmed.hasPrefix("burst_start ") {
        // burst_start <startIdx> <prefix> <dir>
        let parts = splitCommand(trimmed, expected: 4)
        guard parts.count == 4, let startIdx = Int(parts[1]) else {
            emit("err burst_start: expected: burst_start <startIdx> <prefix> <dir>")
            continue
        }
        let prefix = parts[2]
        let dir = URL(fileURLWithPath: parts[3])
        runner.startBurst(dir: dir, prefix: prefix, startIndex: startIdx)
        emit("ok burst_started")
    } else if trimmed == "burst_stop" {
        let r = runner.stopBurst()
        emit("ok burst count=\(r.count) errors=\(r.errors) first=\(r.first) last=\(r.last)")
    } else if trimmed.hasPrefix("/") || trimmed.hasPrefix(".") {
        // Back-compat: bare path means single shot.
        if let err = runner.capture(to: trimmed) {
            emit("err \(err)")
        } else {
            emit("ok \(trimmed)")
        }
    } else {
        emit("err unknown command: \(trimmed.prefix(32))")
    }
}

runner.session.stopRunning()
exit(0)
