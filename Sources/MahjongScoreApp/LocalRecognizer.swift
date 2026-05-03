import Foundation
import Vision
import CoreGraphics
import ImageIO
import MahjongCore

/// Recognizer mode stored in user prefs. Read via `@AppStorage("recognizerModeRaw")`.
enum RecognizerMode: String, CaseIterable, Sendable {
    case claude     // cloud API only
    case local      // on-device CoreML (falls back to Claude for the whole image
                    // if detection returns too few tiles or no model is available)
}

/// End-to-end on-device recognizer. **Experimental** — tile detection on
/// touching-tile rows is an unsolved general problem; works best on photos
/// with visible separation between tiles.
///
/// Pipeline:
/// 1. `VNDetectRectanglesRequest` → candidate tile bounding boxes
/// 2. Filter + cluster boxes by aspect ratio and y-coordinate
/// 3. Crop each box from the source image
/// 4. `TileClassifier.classify` on each crop → (label, confidence)
/// 5. Group tiles into rows; if two y-clusters, upper/lower; else single
///
/// If detection returns too few boxes, the optional `fallback` is used instead.
struct LocalRecognizer: ImageRecognizer {

    enum RecognizeError: Error {
        case imageLoadFailed
        case detectionFailed
        case tooFewTiles(detected: Int)
    }

    let classifier: TileClassifier
    let fallback: ImageRecognizer?
    /// Minimum classifier confidence to accept a label. Below this the tile is
    /// dropped entirely (we'd rather leave it out than emit noise).
    let minConfidence: Float

    init(
        classifier: TileClassifier,
        fallback: ImageRecognizer? = nil,
        minConfidence: Float = 0.35
    ) {
        self.classifier = classifier
        self.fallback = fallback
        self.minConfidence = minConfidence
    }

    func recognize(imageData: Data) async throws -> RecognizedTiles {
        guard let cgImage = Self.loadCGImage(imageData: imageData) else {
            if let fallback { return try await fallback.recognize(imageData: imageData) }
            throw RecognizeError.imageLoadFailed
        }

        let detected = try Self.detectTileBoxes(cgImage: cgImage)
        // Heuristic: a Taiwan hand has ~17 body tiles. If we got wildly fewer,
        // detection probably collapsed touching tiles into a single rectangle —
        // fall back to Claude (or error).
        if detected.count < 10, let fallback {
            return try await fallback.recognize(imageData: imageData)
        }
        if detected.count < 10 {
            throw RecognizeError.tooFewTiles(detected: detected.count)
        }

        var recognized: [RecognizedTile] = []
        for bbox in detected {
            guard let crop = Self.crop(cgImage: cgImage, bbox: bbox) else { continue }
            do {
                let (label, confidence) = try await classifier.classify(crop)
                guard confidence >= minConfidence else { continue }
                guard let tile = try? Tile(label) else { continue }
                recognized.append(RecognizedTile(tile: tile, bbox: bbox))
            } catch {
                continue
            }
        }

        let rows = Self.groupIntoRows(recognized)
        return RecognizedTiles(
            rows: rows,
            flowers: [],          // local detector can't reliably separate flowers yet
            winningTile: nil,     // half-raised-tile heuristic also deferred
            rawResponse: nil
        )
    }

    // MARK: - Detection

    /// Detect candidate tile bounding boxes via Vision. Returns normalized
    /// `BBox` values with top-left origin.
    static func detectTileBoxes(cgImage: CGImage) throws -> [BBox] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.5    // tiles are portrait-ish
        request.maximumAspectRatio = 1.1
        request.minimumSize = 0.015
        request.minimumConfidence = 0.3
        request.maximumObservations = 60
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let obs = request.results else { return [] }

        // Vision's boundingBox uses bottom-left origin in normalized coords.
        // Convert to our top-left convention.
        return obs.map { r in
            let bb = r.boundingBox
            return BBox(
                x: Double(bb.origin.x),
                y: Double(1.0 - bb.origin.y - bb.size.height),
                width: Double(bb.size.width),
                height: Double(bb.size.height)
            )
        }
    }

    // MARK: - Cropping

    static func crop(cgImage: CGImage, bbox: BBox, paddingFraction: Double = 0.03) -> CGImage? {
        let imgW = Double(cgImage.width)
        let imgH = Double(cgImage.height)
        let padX = bbox.width * paddingFraction
        let padY = bbox.height * paddingFraction
        let x = max(0, (bbox.x - padX) * imgW)
        let y = max(0, (bbox.y - padY) * imgH)
        let w = min(imgW - x, (bbox.width + 2 * padX) * imgW)
        let h = min(imgH - y, (bbox.height + 2 * padY) * imgH)
        guard w > 4, h > 4 else { return nil }
        return cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h).integral)
    }

    // MARK: - Row grouping

    /// Group detected tiles into rows by clustering on y-centroid.
    /// If we find two well-separated clusters, return upper/lower; otherwise single.
    static func groupIntoRows(_ tiles: [RecognizedTile]) -> [RecognizedTiles.Row] {
        guard !tiles.isEmpty else { return [] }
        // Sort by y then x
        let sorted = tiles.sorted { a, b in
            let ay = a.bbox.map { $0.y + $0.height / 2 } ?? 0
            let by = b.bbox.map { $0.y + $0.height / 2 } ?? 0
            if abs(ay - by) > 0.08 { return ay < by }
            let ax = a.bbox?.x ?? 0
            let bx = b.bbox?.x ?? 0
            return ax < bx
        }
        // Bucket by y-centroid gap
        var rows: [[RecognizedTile]] = [[]]
        var lastY: Double = -1
        for tile in sorted {
            let yc = (tile.bbox?.y ?? 0) + (tile.bbox?.height ?? 0) / 2
            if lastY >= 0, (yc - lastY) > 0.10 {
                rows.append([])
            }
            rows[rows.count - 1].append(tile)
            lastY = yc
        }
        rows = rows.filter { !$0.isEmpty }

        switch rows.count {
        case 0:
            return []
        case 1:
            return [.init(placement: .single, tiles: rows[0])]
        default:
            // Two or more clusters: treat the top-most as upper, bottom-most as lower.
            // Collapse any stray middle clusters into the nearest row.
            let upper = rows.first!
            let lower = rows.last!
            return [
                .init(placement: .upper, tiles: upper),
                .init(placement: .lower, tiles: lower),
            ]
        }
    }

    // MARK: - Image loading

    static func loadCGImage(imageData: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
