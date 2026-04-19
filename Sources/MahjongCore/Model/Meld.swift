import Foundation

/// The four kinds of meld that can appear in a winning Taiwan 16-tile hand.
public enum MeldKind: String, CaseIterable, Codable, Sendable {
    case pair  // 對 — the eye (2 tiles)
    case chow  // 順子 — three consecutive tiles of the same numeric suit
    case pung  // 刻子 — three identical tiles
    case kong  // 槓 — four identical tiles

    public var requiredTileCount: Int {
        switch self {
        case .pair: 2
        case .chow, .pung: 3
        case .kong: 4
        }
    }
}

/// A validated group of tiles forming a chow, pung, kong, or pair.
///
/// Flowers are never part of a meld — they're tracked separately on the `Hand`.
/// Tiles are stored in canonical sorted order.
public struct Meld: Hashable, Codable, Sendable {
    public let kind: MeldKind
    public let tiles: [Tile]
    public let isConcealed: Bool

    public init(kind: MeldKind, tiles: [Tile], isConcealed: Bool) throws {
        guard tiles.count == kind.requiredTileCount else {
            throw ValidationError.wrongTileCount(kind: kind, got: tiles.count)
        }
        let sorted = tiles.sorted()
        try Self.validateShape(kind: kind, tiles: sorted)
        self.kind = kind
        self.tiles = sorted
        self.isConcealed = isConcealed
    }

    private static func validateShape(kind: MeldKind, tiles: [Tile]) throws {
        if tiles.contains(where: { $0.isFlower }) {
            throw ValidationError.flowerNotAllowed
        }
        switch kind {
        case .pair:
            guard tiles[0] == tiles[1] else { throw ValidationError.pairNotIdentical }
        case .pung:
            guard tiles.allSatisfy({ $0 == tiles[0] }) else {
                throw ValidationError.pungNotIdentical
            }
        case .kong:
            guard tiles.allSatisfy({ $0 == tiles[0] }) else {
                throw ValidationError.kongNotIdentical
            }
        case .chow:
            guard
                case let .numeric(suitA, rankA) = tiles[0],
                case let .numeric(suitB, rankB) = tiles[1],
                case let .numeric(suitC, rankC) = tiles[2]
            else {
                throw ValidationError.chowContainsNonNumeric
            }
            guard suitA == suitB, suitB == suitC else {
                throw ValidationError.chowAcrossSuits
            }
            guard rankB == rankA + 1, rankC == rankB + 1 else {
                throw ValidationError.chowNotConsecutive
            }
        }
    }

    public enum ValidationError: Error, Equatable {
        case wrongTileCount(kind: MeldKind, got: Int)
        case flowerNotAllowed
        case pairNotIdentical
        case pungNotIdentical
        case kongNotIdentical
        case chowContainsNonNumeric
        case chowAcrossSuits
        case chowNotConsecutive
    }

    // MARK: - Convenience

    public var isEye: Bool { kind == .pair }
    public var isKong: Bool { kind == .kong }

    /// A representative tile for the meld — the lowest tile, or the (only) tile kind
    /// for pung/kong/pair. For chows, this is the starting tile (e.g. 3 for a 345 chow).
    public var baseTile: Tile { tiles[0] }

    /// True if every tile in this meld is a terminal (1 or 9 of a numeric suit).
    /// For chows this is always false since they span three ranks.
    public var isAllTerminal: Bool { tiles.allSatisfy { $0.isTerminal } }

    /// True if every tile in this meld is an honor (wind or dragon).
    public var isAllHonor: Bool { tiles.allSatisfy { $0.isHonor } }

    /// The suit of a numeric meld, or `nil` for honor melds.
    public var numericSuit: Suit? {
        if case let .numeric(suit, _) = tiles[0] { return suit }
        return nil
    }
}
