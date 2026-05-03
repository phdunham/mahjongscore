import Foundation

/// A normalized tile bounding box in image-relative coordinates.
/// Origin is the top-left of the image; all four values are in `[0, 1]`.
public struct BBox: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Reject out-of-range or degenerate boxes (tolerate small rounding overshoot).
    public var isValid: Bool {
        let eps = 0.002
        return x >= -eps
            && y >= -eps
            && width > 0
            && height > 0
            && (x + width) <= 1 + eps
            && (y + height) <= 1 + eps
    }
}

/// A recognized tile plus (optionally) its bounding box and a model
/// self-rated confidence in `[0, 1]`. The bbox is used to crop per-tile
/// training samples; the confidence is used to route low-certainty tiles
/// through a focused single-tile re-verification pass.
public struct RecognizedTile: Hashable, Sendable {
    public let tile: Tile
    public let bbox: BBox?
    public let confidence: Double?

    public init(tile: Tile, bbox: BBox? = nil, confidence: Double? = nil) {
        self.tile = tile
        self.bbox = bbox
        self.confidence = confidence
    }
}

/// The result of identifying tiles in a photo.
///
/// Rows are tagged by placement (`upper` / `lower` / `single`) so the UI knows
/// where each row came from in the original layout. The recognizer may also
/// indicate which tile was half-raised (the winning tile).
public struct RecognizedTiles: Hashable, Sendable {

    public enum Placement: String, Hashable, Sendable, Codable {
        case upper    // concealed hand (user convention)
        case lower    // exposed / called melds (user convention)
        case single   // only one row detected; UI decides concealed/exposed
    }

    public struct Row: Hashable, Sendable {
        public let placement: Placement
        public let tiles: [RecognizedTile]

        public init(placement: Placement, tiles: [RecognizedTile]) {
            self.placement = placement
            self.tiles = tiles
        }
    }

    public let rows: [Row]
    public let flowers: [RecognizedTile]
    /// The half-raised winning tile, if detected.
    public let winningTile: RecognizedTile?
    public let rawResponse: String?

    public init(
        rows: [Row] = [],
        flowers: [RecognizedTile] = [],
        winningTile: RecognizedTile? = nil,
        rawResponse: String? = nil
    ) {
        self.rows = rows
        self.flowers = flowers
        self.winningTile = winningTile
        self.rawResponse = rawResponse
    }

    // MARK: - Flat accessors (bbox-agnostic)

    /// Every body tile across all rows, in row order.
    public var bodyTiles: [Tile] { rows.flatMap { $0.tiles.map(\.tile) } }

    /// Body tiles the UI should treat as concealed by default (upper + single).
    public var defaultConcealedTiles: [Tile] {
        rows.filter { $0.placement != .lower }
            .flatMap { $0.tiles.map(\.tile) }
    }

    /// Body tiles the recognizer reported as exposed (lower row only).
    public var reportedExposedTiles: [Tile] {
        rows.filter { $0.placement == .lower }
            .flatMap { $0.tiles.map(\.tile) }
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
