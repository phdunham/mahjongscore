import Foundation
import CreateML
import SwiftUI
import MahjongCore

/// Manages the lifecycle of the on-device tile classifier:
/// - Reads dataset stats from `~/Library/Application Support/MahjongScore/training-data/`
/// - Trains a CoreML image classifier using `CreateML.MLImageClassifier`
/// - Writes the resulting model to app support (atomic swap via temp file)
/// - Reports progress and status for the UI
@MainActor
final class TrainingCoordinator: ObservableObject {

    // MARK: - Types

    enum Status: Equatable {
        case idle
        case training(message: String)
        case succeeded(validationAccuracy: Double?, modelPath: String)
        case failed(message: String)
    }

    struct Stats {
        var totalImages: Int = 0
        var classCounts: [String: Int] = [:]

        var classesWithData: Int {
            classCounts.values.filter { $0 > 0 }.count
        }
        /// Minimum samples-per-class CreateML will actually tolerate. Below this,
        /// the training step either errors or produces a garbage model.
        static let minSamplesPerClass = 5
        /// Soft recommendation for any useful model.
        static let recommendedSamplesPerClass = 20

        var classesBelowMinimum: [String] {
            classCounts.filter { $0.value > 0 && $0.value < Self.minSamplesPerClass }
                .keys.sorted()
        }
        var classesBelowRecommended: [String] {
            classCounts.filter { $0.value > 0 && $0.value < Self.recommendedSamplesPerClass }
                .keys.sorted()
        }
    }

    // MARK: - Published state

    @Published var status: Status = .idle
    @Published var stats: Stats = .init()
    @Published var lastTrainedAt: Date?

    // MARK: - Paths

    // Paths are constant and safe to read from any actor — mark them nonisolated
    // so `TileClassifier.load()` (which isn't main-actor) can reference them
    // without warnings under Swift 6 strict concurrency.
    nonisolated static let supportDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MahjongScore", isDirectory: true)
    }()

    nonisolated static let modelURL: URL = supportDir.appendingPathComponent("TileClassifier.mlmodel")
    nonisolated static let tempModelURL: URL = supportDir.appendingPathComponent("TileClassifier.tmp.mlmodel")

    // MARK: - Init

    init() {
        refreshStats()
    }

    var modelAvailable: Bool {
        FileManager.default.fileExists(atPath: Self.modelURL.path)
    }

    // MARK: - Stats

    func refreshStats() {
        let dataDir = TrainingDataSaver.rootDir
        var counts: [String: Int] = [:]
        var total = 0

        for notation in Self.expectedTileNotations {
            let classDir = dataDir.appendingPathComponent(notation)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: classDir.path)) ?? []
            let imageCount = files.filter { name in
                let lower = name.lowercased()
                return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")
            }.count
            counts[notation] = imageCount
            total += imageCount
        }

        var s = Stats()
        s.totalImages = total
        s.classCounts = counts
        self.stats = s
    }

    // MARK: - Training

    /// True if there are enough classes-with-enough-samples to attempt training.
    /// CreateML needs at least 2 labels with ≥ 2 images each to produce anything.
    var readyToTrain: Bool {
        stats.classCounts.values.filter { $0 >= Stats.minSamplesPerClass }.count >= 2
    }

    func trainNow() async {
        guard readyToTrain else {
            status = .failed(
                message: "Not enough data. Need at least 2 tile classes with ≥ \(Stats.minSamplesPerClass) images each. Current: \(stats.classesWithData) classes have any data."
            )
            return
        }
        status = .training(message: "Preparing data…")

        let dataDir = TrainingDataSaver.rootDir
        let tempURL = Self.tempModelURL
        let finalURL = Self.modelURL

        do {
            try? FileManager.default.createDirectory(
                at: Self.supportDir, withIntermediateDirectories: true
            )

            status = .training(message: "Training classifier — this can take several minutes.")
            let (accuracy, modelPath) = try await Task.detached(priority: .userInitiated) { () throws -> (Double?, String) in
                let dataSource = MLImageClassifier.DataSource.labeledDirectories(at: dataDir)
                // Modern init: parameter name is `augmentation:` (no "Options"
                // suffix, that's the deprecated form), and the feature extractor
                // is selected via `algorithm:` rather than a flat parameter.
                let params = MLImageClassifier.ModelParameters(
                    validation: .split(strategy: .automatic),
                    maxIterations: 25,
                    augmentation: [.crop, .flip, .rotation, .exposure, .blur, .noise]
                )

                let classifier = try MLImageClassifier(
                    trainingData: dataSource, parameters: params
                )
                try classifier.write(to: tempURL)

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: finalURL)

                let acc: Double? = {
                    let err = classifier.validationMetrics.classificationError
                    return err.isNaN ? nil : (1.0 - err)
                }()
                return (acc, finalURL.path)
            }.value

            lastTrainedAt = Date()
            status = .succeeded(validationAccuracy: accuracy, modelPath: modelPath)
        } catch {
            status = .failed(message: "\(error)")
        }
    }

    // MARK: - Expected tile notations (42 classes)

    static let expectedTileNotations: [String] = {
        var out: [String] = []
        for suit in ["m", "p", "s"] {
            for r in 1...9 { out.append("\(r)\(suit)") }
        }
        out.append(contentsOf: ["Ew", "Sw", "Ww", "Nw", "Rd", "Gd", "Wd"])
        for i in 1...8 { out.append("\(i)f") }
        return out
    }()
}
