// ClassifyTile — runs CoreMLTileClassifier over image(s) from the command line.
//
// Single image:   ClassifyTile path/to/tile.jpeg
// Validate set:   ClassifyTile --validate tile-photos/
//
// Validation mode walks the same directory layout capture-tiles.sh produces
// (<dir>/<notation>/<notation>_NNNN.jpeg), uses the subdirectory name as
// ground truth, and reports per-class and overall accuracy.

import Foundation
import MahjongCore

func die(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    die("""
        Usage:
          ClassifyTile <image>
          ClassifyTile --validate <dir>
        """)
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { usage() }

// MARK: - Load classifier

let classifier: CoreMLTileClassifier
do {
    classifier = try CoreMLTileClassifier()
} catch CoreMLTileClassifier.ClassifierError.modelNotFound {
    die("""
        Model not found. Train a Create ML image classifier, export
        TileClassifier.mlmodel, drop it into Sources/MahjongCore/Resources/,
        and run `swift build` again.
        """)
} catch {
    die("Failed to load classifier: \(error)")
}

// MARK: - Modes

if args[0] == "--validate" {
    guard args.count == 2 else { usage() }
    let root = URL(fileURLWithPath: args[1])
    validate(root: root)
} else {
    let url = URL(fileURLWithPath: args[0])
    classifyOne(url: url)
}

// MARK: - Single image

func classifyOne(url: URL) {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        die("Read failed: \(error.localizedDescription)")
    }
    do {
        let pred = try classifier.classify(imageData: data)
        print(String(format: "%@  (%.3f)", pred.tile.notation, pred.confidence))
    } catch {
        die("Classify failed: \(error)")
    }
}

// MARK: - Validate a directory tree

func validate(root: URL) {
    let fm = FileManager.default
    var entries: [URL]
    do {
        entries = try fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    } catch {
        die("Cannot list \(root.path): \(error.localizedDescription)")
    }

    // Immediate subdirs only — each one's name is the ground-truth label.
    let classDirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    guard !classDirs.isEmpty else {
        die("No subdirectories in \(root.path) — expected one folder per tile class.")
    }

    var perClass: [(label: String, correct: Int, total: Int, avgConf: Double, mistakes: [(String, String)])] = []
    var grandCorrect = 0
    var grandTotal = 0

    for dir in classDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let label = dir.lastPathComponent
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "jpeg" || $0.pathExtension.lowercased() == "jpg" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            ?? []
        if files.isEmpty { continue }

        FileHandle.standardError.write(Data("[\(label)] \(files.count) files\n".utf8))

        var correct = 0
        var confSum = 0.0
        var mistakes: [(String, String)] = []  // (filename, predicted label)

        for (idx, file) in files.enumerated() {
            if idx % 10 == 0 {
                FileHandle.standardError.write(Data("  \(idx)/\(files.count) \(file.lastPathComponent)\n".utf8))
            }
            autoreleasepool {
                guard let data = try? Data(contentsOf: file) else { return }
                do {
                    let pred = try classifier.classify(imageData: data)
                    confSum += Double(pred.confidence)
                    if pred.tile.notation == label {
                        correct += 1
                    } else if mistakes.count < 3 {
                        mistakes.append((file.lastPathComponent, pred.tile.notation))
                    }
                } catch {
                    // Skip unreadable or unclassifiable images.
                }
            }
        }
        let total = files.count
        grandCorrect += correct
        grandTotal += total
        perClass.append((label, correct, total, confSum / Double(max(total, 1)), mistakes))
    }

    print(String(format: "%-4@ %6@ %10@ %@",
                 "tile" as NSString, "acc" as NSString,
                 "conf" as NSString, "mistakes (up to 3)" as NSString))
    print(String(repeating: "-", count: 72))
    for r in perClass {
        let acc = Double(r.correct) / Double(max(r.total, 1)) * 100
        let mistakeStr = r.mistakes.map { "\($0.0)→\($0.1)" }.joined(separator: ", ")
        print(String(format: "%-4@ %5.1f%% (%3d/%3d) %5.2f  %@",
                     r.label as NSString, acc, r.correct, r.total, r.avgConf,
                     mistakeStr as NSString))
    }
    print(String(repeating: "-", count: 72))
    let overall = Double(grandCorrect) / Double(max(grandTotal, 1)) * 100
    print(String(format: "overall: %.2f%%  (%d/%d)", overall, grandCorrect, grandTotal))
}
