import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MahjongCore

/// Crops per-tile training samples from a scored-hand photo and files them into
/// `~/Library/Application Support/MahjongScore/training-data/<notation>/`.
///
/// Input: the original photo bytes plus a list of `(label, bbox)` pairs, where
/// labels are the user's final (corrected) tile identities. Every tile with a
/// valid bbox gets cropped (with padding) and saved as JPEG.
enum TrainingDataSaver {

    static let rootDir: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support
            .appendingPathComponent("MahjongScore", isDirectory: true)
            .appendingPathComponent("training-data", isDirectory: true)
    }()

    struct LabeledBBox {
        let tile: Tile
        let bbox: BBox
    }

    struct Result {
        var saved: Int = 0
        var skippedNoBBox: Int = 0
        var skippedInvalidBBox: Int = 0
        var skippedCropFailed: Int = 0
    }

    /// Save cropped tile images for each labeled bbox. Tiles without a bbox
    /// (user-added or missing from the recognizer) are tallied as skipped.
    /// Returns aggregate counts.
    @discardableResult
    static func save(
        photoData: Data,
        labeled: [LabeledBBox],
        unbboxedLabelCount: Int = 0,
        paddingFraction: Double = 0.08
    ) -> Result {
        var result = Result()
        result.skippedNoBBox = unbboxedLabelCount

        guard
            let source = CGImageSourceCreateWithData(photoData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            result.skippedCropFailed = labeled.count
            return result
        }

        let timestamp = filesystemTimestamp()
        for (index, entry) in labeled.enumerated() {
            guard entry.bbox.isValid else {
                result.skippedInvalidBBox += 1
                continue
            }
            guard let cropped = cropCGImage(cgImage, bbox: entry.bbox, paddingFraction: paddingFraction) else {
                result.skippedCropFailed += 1
                continue
            }
            let classDir = rootDir.appendingPathComponent(entry.tile.notation, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: classDir, withIntermediateDirectories: true)
            } catch {
                result.skippedCropFailed += 1
                continue
            }
            let filename = "\(timestamp)-\(index).jpg"
            let url = classDir.appendingPathComponent(filename)
            if writeJPEG(cropped, to: url) {
                result.saved += 1
            } else {
                result.skippedCropFailed += 1
            }
        }
        return result
    }

    // MARK: - Internals

    private static func cropCGImage(
        _ cgImage: CGImage,
        bbox: BBox,
        paddingFraction: Double
    ) -> CGImage? {
        let imgW = Double(cgImage.width)
        let imgH = Double(cgImage.height)
        let padX = bbox.width * paddingFraction
        let padY = bbox.height * paddingFraction

        let x = max(0, (bbox.x - padX) * imgW)
        let y = max(0, (bbox.y - padY) * imgH)
        let w = min(imgW - x, (bbox.width + 2 * padX) * imgW)
        let h = min(imgH - y, (bbox.height + 2 * padY) * imgH)

        guard w > 4, h > 4 else { return nil }
        let rect = CGRect(x: x, y: y, width: w, height: h).integral
        return cgImage.cropping(to: rect)
    }

    private static func writeJPEG(_ cgImage: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else { return false }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func filesystemTimestamp() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
