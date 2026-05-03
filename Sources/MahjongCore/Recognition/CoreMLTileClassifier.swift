import CoreML
import Foundation
@preconcurrency import Vision

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// On-device classifier for a single cropped tile image, backed by a Core ML
/// model trained in Create ML. Expects the model's class labels to be valid
/// tile notations (e.g. `"1m"`, `"Ew"`, `"Rd"`, `"5f"`) — i.e. the same
/// strings as the subdirectory names under `tile-photos/`, so the folder
/// structure you trained on already matches `Tile.init(_:)`.
///
/// This is not a full `ImageRecognizer`: it does no segmentation. Pair it
/// with something that crops a full-hand photo into per-tile images (Claude,
/// a future object detector, or hand-written CV) and feed each crop here.
public final class CoreMLTileClassifier: Sendable {

    public enum ClassifierError: Error, Equatable {
        /// `TileClassifier.mlmodelc` wasn't found in the module's resource bundle.
        /// Add `TileClassifier.mlmodel` to `Sources/MahjongCore/Resources/` and
        /// rebuild so SwiftPM compiles it.
        case modelNotFound
        case modelLoadFailed(String)
        /// Vision produced no `VNClassificationObservation` results.
        case noResults
        /// The model returned a label that isn't a valid tile notation.
        case unknownLabel(String)
        case imageDecodeFailed
    }

    public struct Prediction: Sendable, Equatable {
        public let tile: Tile
        public let confidence: Float
        public init(tile: Tile, confidence: Float) {
            self.tile = tile
            self.confidence = confidence
        }
    }

    /// Name (without extension) of the compiled model in the resource bundle.
    public static let defaultModelName = "TileClassifier"

    private let vnModel: VNCoreMLModel

    public init(modelName: String = CoreMLTileClassifier.defaultModelName) throws {
        let url = try Self.locateCompiledModel(named: modelName)
        let mlModel: MLModel
        do {
            mlModel = try MLModel(contentsOf: url)
        } catch {
            throw ClassifierError.modelLoadFailed(error.localizedDescription)
        }
        do {
            self.vnModel = try VNCoreMLModel(for: mlModel)
        } catch {
            throw ClassifierError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Returns a URL to a compiled `.mlmodelc`. Prefers one already in the
    /// resource bundle (Xcode builds put it there); falls back to compiling
    /// the raw `.mlmodel` at runtime and caching the result under
    /// `~/Library/Caches/MahjongCore/` keyed by source mtime. This is what
    /// makes plain `swift build` (which only copies the .mlmodel) work.
    private static func locateCompiledModel(named modelName: String) throws -> URL {
        if let url = Bundle.module.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }
        guard let rawURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodel") else {
            throw ClassifierError.modelNotFound
        }
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MahjongCore", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachedURL = cacheDir.appendingPathComponent("\(modelName).mlmodelc")

        let rawMtime = (try? rawURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        let cachedMtime = (try? cachedURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast

        if fm.fileExists(atPath: cachedURL.path), cachedMtime >= rawMtime {
            return cachedURL
        }

        let compiledTemp: URL
        do {
            compiledTemp = try MLModel.compileModel(at: rawURL)
        } catch {
            throw ClassifierError.modelLoadFailed("compile failed: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: cachedURL)
        do {
            try fm.moveItem(at: compiledTemp, to: cachedURL)
        } catch {
            // Fall back to using the temp path directly if caching fails.
            return compiledTemp
        }
        return cachedURL
    }

    // MARK: - Classification

    /// Classifies a cropped tile image. `imageData` is JPEG or PNG bytes.
    public func classify(imageData: Data) throws -> Prediction {
        guard let cgImage = Self.decodeCGImage(from: imageData) else {
            throw ClassifierError.imageDecodeFailed
        }
        return try classify(cgImage: cgImage)
    }

    /// Classifies a cropped tile image. Prefer this overload when you already
    /// have a `CGImage` (e.g. from cropping a larger photo) — it avoids a
    /// redundant decode.
    public func classify(cgImage: CGImage) throws -> Prediction {
        // Vision/Core ML allocate autoreleased temporaries per request.
        // Without a pool, tight loops accumulate them until the process
        // hits limits and segfaults. `autoreleasepool` here keeps each
        // call self-contained regardless of caller discipline.
        var captured: Result<Prediction, Error> = .failure(ClassifierError.noResults)
        autoreleasepool {
            do {
                let request = VNCoreMLRequest(model: vnModel)
                // `.scaleFit` letterboxes the whole image into the model's
                // input box, matching what Create ML sees at training time.
                // `.centerCrop` chops the edges and can cut off tiles that
                // aren't dead-center in the frame.
                request.imageCropAndScaleOption = .scaleFit

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                guard let results = request.results as? [VNClassificationObservation],
                      let top = results.first else {
                    captured = .failure(ClassifierError.noResults)
                    return
                }
                guard let tile = try? Tile(top.identifier) else {
                    captured = .failure(ClassifierError.unknownLabel(top.identifier))
                    return
                }
                captured = .success(Prediction(tile: tile, confidence: top.confidence))
            } catch {
                captured = .failure(error)
            }
        }
        return try captured.get()
    }

    // MARK: - Helpers

    private static func decodeCGImage(from data: Data) -> CGImage? {
        #if canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #elseif canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #else
        return nil
        #endif
    }
}
