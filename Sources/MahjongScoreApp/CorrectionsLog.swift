import Foundation
import MahjongCore

/// Writes per-hand correction data to `~/Library/Application Support/MahjongScore/corrections/`.
/// Each hand produces two files sharing a timestamp prefix:
///
///     2026-04-19T15-30-12Z.jpg    — the input photo
///     2026-04-19T15-30-12Z.json   — recognizer output + final corrected state
///
/// Purpose: build a labeled dataset over time for the future on-device CoreML
/// classifier. "No correction needed" cases are equally useful (they confirm
/// the recognizer got it right).
enum CorrectionsLog {

    static let directory: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support
            .appendingPathComponent("MahjongScore", isDirectory: true)
            .appendingPathComponent("corrections", isDirectory: true)
    }()

    enum LogError: Error {
        case invalidPhotoData
    }

    static func save(
        photoData: Data,
        photoMediaType: String,
        recognized: RecognizedTiles,
        correctedConcealed: [Tile],
        correctedExposed: [Tile],
        correctedFlowers: [Tile],
        correctedWinning: Tile,
        model: String
    ) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let timestamp = Self.timestampForFilename()
        let ext: String = photoMediaType.hasSuffix("png") ? "png" : "jpg"
        let photoURL = directory.appendingPathComponent("\(timestamp).\(ext)")
        try photoData.write(to: photoURL)

        let entry = Entry(
            timestamp: timestamp,
            model: model,
            photoFile: photoURL.lastPathComponent,
            recognized: Entry.Recognized(
                rows: recognized.rows.map { row in
                    Entry.Row(
                        placement: row.placement.rawValue,
                        tiles: row.tiles.map(\.notation)
                    )
                },
                flowers: recognized.flowers.map(\.notation),
                winningTile: recognized.winningTile?.notation
            ),
            corrected: Entry.Corrected(
                concealed: correctedConcealed.map(\.notation),
                exposed: correctedExposed.map(\.notation),
                flowers: correctedFlowers.map(\.notation),
                winningTile: correctedWinning.notation
            )
        )

        let jsonURL = directory.appendingPathComponent("\(timestamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(to: jsonURL)
    }

    private static func timestampForFilename() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // filesystem-safe form: replace colons and periods
        return fmt.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    struct Entry: Encodable {
        let timestamp: String
        let model: String
        let photoFile: String
        let recognized: Recognized
        let corrected: Corrected

        struct Recognized: Encodable {
            let rows: [Row]
            let flowers: [String]
            let winningTile: String?
        }
        struct Row: Encodable {
            let placement: String
            let tiles: [String]
        }
        struct Corrected: Encodable {
            let concealed: [String]
            let exposed: [String]
            let flowers: [String]
            let winningTile: String
        }
    }
}
