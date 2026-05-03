// BenchmarkClaude — samples N images per class from tile-photos, sends each
// to ClaudeRecognizer, and reports per-class and overall per-tile accuracy.
//
// The recognizer was designed for full-hand photos (rows, flowers, winning
// tile). Feeding it a single-tile crop is off-label; we extract whatever
// single tile appears in the response (body tile, flower, or winning tile).
//
// Usage:
//   BenchmarkClaude [--dir tile-photos] [--samples 3] [--concurrency 4]
//                   [--model haiku|sonnet|opus]
//
// Requires ANTHROPIC_API_KEY in the environment.
//
// Cost: 3 samples × 42 classes = 126 API calls. With claude-haiku-4-5
// that's typically well under $1.

import Foundation
import MahjongCore

// MARK: - Argument parsing

struct Options {
    var dir: URL = URL(fileURLWithPath: "tile-photos")
    var samplesPerClass: Int = 3
    var concurrency: Int = 4
    var model: ClaudeRecognizer.Model = .haiku45
}

func parseArgs() -> Options {
    var opts = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--dir":
            guard let v = it.next() else { usage("missing value for --dir") }
            opts.dir = URL(fileURLWithPath: v)
        case "--samples":
            guard let v = it.next(), let n = Int(v), n > 0 else { usage("bad --samples") }
            opts.samplesPerClass = n
        case "--concurrency":
            guard let v = it.next(), let n = Int(v), n > 0 else { usage("bad --concurrency") }
            opts.concurrency = n
        case "--model":
            guard let v = it.next() else { usage("missing --model") }
            switch v {
            case "haiku":  opts.model = .haiku45
            case "sonnet": opts.model = .sonnet46
            case "opus":   opts.model = .opus47
            default: usage("--model must be haiku|sonnet|opus")
            }
        case "-h", "--help":
            print("""
            Usage: BenchmarkClaude [--dir DIR] [--samples N]
                                   [--concurrency N] [--model haiku|sonnet|opus]
            """)
            exit(0)
        default:
            usage("unknown arg: \(arg)")
        }
    }
    return opts
}

func usage(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(2)
}

// MARK: - Sampling

struct WorkItem: Sendable {
    let label: String
    let url: URL
}

func sampleWork(dir: URL, samplesPerClass: Int) throws -> [WorkItem] {
    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    let classDirs = entries.filter {
        (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    var work: [WorkItem] = []
    for classDir in classDirs {
        let label = classDir.lastPathComponent
        let files = ((try? fm.contentsOfDirectory(at: classDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "jpeg" || $0.pathExtension.lowercased() == "jpg" }
        guard !files.isEmpty else { continue }
        // Deterministic sample: evenly spaced across the sorted list, so
        // repeat runs cover the same images and are comparable.
        let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let step = max(sorted.count / samplesPerClass, 1)
        let picks = stride(from: 0, to: sorted.count, by: step).prefix(samplesPerClass)
        for i in picks {
            work.append(WorkItem(label: label, url: sorted[i]))
        }
    }
    return work
}

// MARK: - Recognize one

struct Outcome: Sendable {
    let item: WorkItem
    let predicted: String?   // nil if no tile extracted
    let error: String?
}

func extractPredictedTile(_ r: RecognizedTiles) -> String? {
    if let t = r.bodyTiles.first { return t.notation }
    if let t = r.flowers.first { return t.tile.notation }
    if let t = r.winningTile { return t.tile.notation }
    return nil
}

func classify(_ item: WorkItem, recognizer: ClaudeRecognizer) async -> Outcome {
    // Retry rate-limit errors (429 and 529 overloaded) with exponential
    // backoff. Everything else fails fast.
    var attempt = 0
    let maxAttempts = 6
    while true {
        attempt += 1
        do {
            let data = try Data(contentsOf: item.url)
            let result = try await recognizer.recognize(imageData: data)
            return Outcome(item: item, predicted: extractPredictedTile(result), error: nil)
        } catch let err as ClaudeRecognizer.RecognitionError {
            if case .apiError(let status, _) = err,
               (status == 429 || status == 529),
               attempt < maxAttempts {
                // Exponential backoff with jitter: 2s, 4s, 8s, 16s, 32s.
                let base = pow(2.0, Double(attempt))
                let jitter = Double.random(in: 0..<1)
                try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                continue
            }
            return Outcome(item: item, predicted: nil, error: "\(err)")
        } catch {
            return Outcome(item: item, predicted: nil, error: "\(error)")
        }
    }
}

// MARK: - Driver (bounded concurrency via sliding task group)

func runBenchmark(
    work: [WorkItem],
    recognizer: ClaudeRecognizer,
    concurrency: Int
) async -> [Outcome] {
    var results: [Outcome] = []
    var completed = 0
    let total = work.count

    await withTaskGroup(of: Outcome.self) { group in
        var nextIndex = 0
        // Seed with up to `concurrency` in-flight tasks.
        while nextIndex < min(concurrency, total) {
            let item = work[nextIndex]
            group.addTask { await classify(item, recognizer: recognizer) }
            nextIndex += 1
        }
        // Each time one finishes, add the next (if any) so we maintain
        // a sliding window of at most `concurrency` live requests.
        while let outcome = await group.next() {
            results.append(outcome)
            completed += 1
            let mark = outcome.error != nil ? "!" :
                (outcome.predicted == outcome.item.label ? "." : "x")
            FileHandle.standardError.write(Data(mark.utf8))
            if completed % 20 == 0 {
                FileHandle.standardError.write(Data(" \(completed)/\(total)\n".utf8))
            }
            if nextIndex < total {
                let item = work[nextIndex]
                group.addTask { await classify(item, recognizer: recognizer) }
                nextIndex += 1
            }
        }
    }
    FileHandle.standardError.write(Data("\n".utf8))
    return results
}

// MARK: - Reporting

func report(_ results: [Outcome]) {
    // Group by label.
    var byLabel: [String: [Outcome]] = [:]
    for r in results { byLabel[r.item.label, default: []].append(r) }

    print(String(format: "%-4@ %10@ %8@  %@",
                 "tile" as NSString, "accuracy" as NSString,
                 "errors" as NSString, "mistakes (up to 3)" as NSString))
    print(String(repeating: "-", count: 72))

    var grandCorrect = 0
    var grandTotal = 0
    var grandErrors = 0

    for label in byLabel.keys.sorted() {
        let group = byLabel[label]!
        let correct = group.filter { $0.predicted == label }.count
        let errors = group.filter { $0.error != nil }.count
        let total = group.count
        grandCorrect += correct
        grandTotal += total
        grandErrors += errors
        let mistakes = group
            .filter { $0.error == nil && $0.predicted != label }
            .prefix(3)
            .map { "\($0.item.url.lastPathComponent)→\($0.predicted ?? "nil")" }
            .joined(separator: ", ")
        let acc = Double(correct) / Double(max(total, 1)) * 100
        print(String(format: "%-4@ %6.1f%% (%d/%d) %4d err  %@",
                     label as NSString, acc, correct, total, errors,
                     mistakes as NSString))
    }
    print(String(repeating: "-", count: 72))
    let overall = Double(grandCorrect) / Double(max(grandTotal, 1)) * 100
    print(String(format: "overall: %.2f%%  (%d/%d),  %d errors",
                 overall, grandCorrect, grandTotal, grandErrors))

    // Surface up to 5 distinct error messages so we can see what actually
    // went wrong when the error count is non-trivial.
    if grandErrors > 0 {
        var seen = Set<String>()
        var samples: [String] = []
        for r in results {
            guard let e = r.error else { continue }
            let head = String(e.prefix(160))
            if !seen.contains(head) {
                seen.insert(head)
                samples.append(head)
                if samples.count >= 5 { break }
            }
        }
        print("\nError samples:")
        for (i, s) in samples.enumerated() {
            print("  [\(i + 1)] \(s)")
        }
    }
}

// MARK: - Main (top-level)

let opts = parseArgs()

guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
    usage("ANTHROPIC_API_KEY not set in environment.")
}

let work: [WorkItem]
do {
    work = try sampleWork(dir: opts.dir, samplesPerClass: opts.samplesPerClass)
} catch {
    usage("Cannot sample from \(opts.dir.path): \(error.localizedDescription)")
}

FileHandle.standardError.write(Data("""
Dir:          \(opts.dir.path)
Model:        \(opts.model.rawValue)
Samples/tile: \(opts.samplesPerClass)
Concurrency:  \(opts.concurrency)
Total calls:  \(work.count)
\n
""".utf8))

let recognizer = ClaudeRecognizer(apiKey: apiKey, model: opts.model)

let results = await runBenchmark(
    work: work, recognizer: recognizer, concurrency: opts.concurrency
)

report(results)
