import Foundation

/// Which group in a `Hand` was completed by the winning tile.
public enum WinCompletion: Hashable, Codable, Sendable {
    /// The winning tile completed one of the body melds (identified by index into `Hand.melds`).
    case meld(index: Int)
    /// The winning tile completed the pair (the eye) — a single-tile wait (單釣).
    case eye
}

/// A complete, validated winning hand for Taiwan 16-tile mahjong.
///
/// Shape:
/// - Exactly **5 body melds** (each chow / pung / kong)
/// - Exactly **1 pair** as the eye
/// - Zero or more flower tiles (max 8)
/// - One designated winning tile, which must belong to one of the body melds or the eye
public struct Hand: Hashable, Codable, Sendable {
    public let melds: [Meld]
    public let eye: Meld
    public let flowers: [Tile]
    public let winningTile: Tile
    public let winCompletes: WinCompletion

    public init(
        melds: [Meld],
        eye: Meld,
        flowers: [Tile] = [],
        winningTile: Tile,
        winCompletes: WinCompletion
    ) throws {
        guard melds.count == 5 else {
            throw ValidationError.wrongMeldCount(got: melds.count)
        }
        if melds.contains(where: { $0.kind == .pair }) {
            throw ValidationError.bodyMeldIsPair
        }
        guard eye.kind == .pair else {
            throw ValidationError.eyeNotPair
        }
        if flowers.contains(where: { !$0.isFlower }) {
            throw ValidationError.nonFlowerInFlowerList
        }
        if flowers.count > 8 {
            throw ValidationError.tooManyFlowers(got: flowers.count)
        }
        // A flower tile never appears more than once on the table.
        if Set(flowers).count != flowers.count {
            throw ValidationError.duplicateFlowers
        }
        try Self.validateWinningTile(
            winningTile: winningTile,
            melds: melds,
            eye: eye,
            winCompletes: winCompletes
        )

        self.melds = melds
        self.eye = eye
        self.flowers = flowers.sorted()
        self.winningTile = winningTile
        self.winCompletes = winCompletes
    }

    private static func validateWinningTile(
        winningTile: Tile,
        melds: [Meld],
        eye: Meld,
        winCompletes: WinCompletion
    ) throws {
        if winningTile.isFlower {
            throw ValidationError.winningTileIsFlower
        }
        switch winCompletes {
        case .eye:
            guard eye.tiles.contains(winningTile) else {
                throw ValidationError.winningTileNotInCompletedGroup
            }
        case .meld(let i):
            guard melds.indices.contains(i) else {
                throw ValidationError.winCompletionIndexOutOfRange
            }
            guard melds[i].tiles.contains(winningTile) else {
                throw ValidationError.winningTileNotInCompletedGroup
            }
        }
    }

    public enum ValidationError: Error, Equatable {
        case wrongMeldCount(got: Int)
        case bodyMeldIsPair
        case eyeNotPair
        case nonFlowerInFlowerList
        case tooManyFlowers(got: Int)
        case duplicateFlowers
        case winningTileIsFlower
        case winCompletionIndexOutOfRange
        case winningTileNotInCompletedGroup
    }
}

// MARK: - Convenience derived properties

public extension Hand {
    /// Every tile in the hand, excluding flowers. Sorted canonically.
    var allBodyTiles: [Tile] {
        (melds.flatMap(\.tiles) + eye.tiles).sorted()
    }

    /// All body melds plus the eye, in that order.
    var meldsIncludingEye: [Meld] { melds + [eye] }

    var chows: [Meld] { melds.filter { $0.kind == .chow } }
    var pungs: [Meld] { melds.filter { $0.kind == .pung } }
    var kongs: [Meld] { melds.filter { $0.kind == .kong } }

    /// True when every body meld and the eye were concealed — i.e. 門清/門前清 condition
    /// before accounting for the winning tile (self-draw vs. discard is in `WinContext`).
    var isFullyConcealed: Bool {
        melds.allSatisfy(\.isConcealed) && eye.isConcealed
    }

    /// The meld (or eye) that the winning tile completed.
    var completedGroup: Meld {
        switch winCompletes {
        case .eye: eye
        case .meld(let i): melds[i]
        }
    }
}
