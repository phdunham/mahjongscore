import Foundation

/// The result of identifying tiles in a photo.
///
/// The recognizer reports layout information:
/// - **Rows** — one or two body-tile rows, each tagged `upper` / `lower` / `single`.
///   By user convention: upper = concealed hand, lower = exposed (called) melds.
///   A single-row photo is ambiguous; the UI provides a toggle.
/// - **Flowers** — listed separately from the body rows.
/// - **Winning tile** — the half-raised tile if visible, used to auto-detect which
///   tile completed the hand.
public struct RecognizedTiles: Hashable, Sendable {

    public enum Placement: String, Hashable, Sendable, Codable {
        case upper    // upper row in a two-row photo → concealed by user convention
        case lower    // lower row in a two-row photo → exposed
        case single   // the photo only has one row → UI decides concealed/exposed
    }

    public struct Row: Hashable, Sendable {
        public let placement: Placement
        public let tiles: [Tile]

        public init(placement: Placement, tiles: [Tile]) {
            self.placement = placement
            self.tiles = tiles
        }
    }

    public let rows: [Row]
    public let flowers: [Tile]
    /// The half-raised tile that completed the hand, if detected in the photo.
    public let winningTile: Tile?
    public let rawResponse: String?

    public init(
        rows: [Row] = [],
        flowers: [Tile] = [],
        winningTile: Tile? = nil,
        rawResponse: String? = nil
    ) {
        self.rows = rows
        self.flowers = flowers
        self.winningTile = winningTile
        self.rawResponse = rawResponse
    }

    // MARK: - Flat accessors

    /// Every body tile across all rows, in row order.
    public var bodyTiles: [Tile] { rows.flatMap(\.tiles) }

    /// Body tiles the UI should treat as concealed by default (upper row + single row).
    public var defaultConcealedTiles: [Tile] {
        rows.filter { $0.placement != .lower }.flatMap(\.tiles)
    }

    /// Body tiles the recognizer reports as exposed (lower row only).
    public var reportedExposedTiles: [Tile] {
        rows.filter { $0.placement == .lower }.flatMap(\.tiles)
    }

    /// True if the photo had exactly one row (UI must disambiguate).
    public var isSingleRow: Bool {
        rows.count == 1 && rows[0].placement == .single
    }
}

/// Implementations turn an image into a list of tiles. `ClaudeRecognizer` is the
/// v1 implementation; a `CoreMLRecognizer` can be swapped in later for on-device
/// recognition with no other changes to the pipeline.
public protocol ImageRecognizer: Sendable {
    /// - Parameter imageData: JPEG or PNG bytes.
    func recognize(imageData: Data) async throws -> RecognizedTiles
}
