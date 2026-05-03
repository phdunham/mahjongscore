import Foundation
import CoreML
import Vision
import CoreGraphics

/// Thin wrapper around a CoreML tile-classification model loaded from disk.
/// Exposes a single `classify(_:)` async method that runs a Vision request
/// against a cropped tile image and returns the best label + confidence.
final class TileClassifier: @unchecked Sendable {
    // @unchecked: `vnModel` is immutable after init, and VNCoreMLModel is
    // documented as safe to use concurrently across queues.

    enum LoadError: Error {
        case missingModel
        case compilationFailed(Error)
        case invalidModel(Error)
    }

    enum ClassifyError: Error {
        case requestFailed(Error)
        case noResult
    }

    private let vnModel: VNCoreMLModel

    /// Compiles and loads the model at `modelURL`. Returns nil if the file
    /// doesn't exist yet (e.g. before the user has trained one).
    static func load(modelURL: URL = TrainingCoordinator.modelURL) throws -> TileClassifier {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LoadError.missingModel
        }
        let compiledURL: URL
        do {
            compiledURL = try MLModel.compileModel(at: modelURL)
        } catch {
            throw LoadError.compilationFailed(error)
        }
        do {
            let mlModel = try MLModel(contentsOf: compiledURL)
            let vn = try VNCoreMLModel(for: mlModel)
            return TileClassifier(vnModel: vn)
        } catch {
            throw LoadError.invalidModel(error)
        }
    }

    private init(vnModel: VNCoreMLModel) {
        self.vnModel = vnModel
    }

    /// Classify a cropped tile image. Returns the top label's identifier
    /// (a tile notation string like "5p") and its confidence in `[0, 1]`.
    func classify(_ cgImage: CGImage) async throws -> (label: String, confidence: Float) {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { req, err in
                if let err {
                    continuation.resume(throwing: ClassifyError.requestFailed(err))
                    return
                }
                guard
                    let results = req.results as? [VNClassificationObservation],
                    let top = results.first
                else {
                    continuation.resume(throwing: ClassifyError.noResult)
                    return
                }
                continuation.resume(returning: (top.identifier, top.confidence))
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ClassifyError.requestFailed(error))
            }
        }
    }
}
