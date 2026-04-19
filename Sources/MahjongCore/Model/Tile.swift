import Foundation

/// A numbered suit in Taiwan 16-tile mahjong.
public enum Suit: String, CaseIterable, Codable, Sendable, Comparable {
    case man = "m"  // 萬 (characters / cracks)
    case pin = "p"  // 筒 (dots / circles)
    case sou = "s"  // 條 (bamboo / bams)

    public var displayName: String {
        switch self {
        case .man: "萬"
        case .pin: "筒"
        case .sou: "條"
        }
    }

    private var order: Int {
        switch self { case .man: 0; case .pin: 1; case .sou: 2 }
    }

    public static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.order < rhs.order }
}

public enum Wind: String, CaseIterable, Codable, Sendable, Comparable {
    case east = "E"
    case south = "S"
    case west = "W"
    case north = "N"

    public var displayName: String {
        switch self {
        case .east: "東"
        case .south: "南"
        case .west: "西"
        case .north: "北"
        }
    }

    /// 1-based wind index used by flower-seat matching (1=E, 2=S, 3=W, 4=N).
    public var seatIndex: Int {
        switch self { case .east: 1; case .south: 2; case .west: 3; case .north: 4 }
    }

    public static func < (lhs: Wind, rhs: Wind) -> Bool { lhs.seatIndex < rhs.seatIndex }
}

public enum Dragon: String, CaseIterable, Codable, Sendable, Comparable {
    case red    // 中
    case green  // 發
    case white  // 白

    public var displayName: String {
        switch self { case .red: "中"; case .green: "發"; case .white: "白" }
    }

    private var order: Int {
        switch self { case .red: 0; case .green: 1; case .white: 2 }
    }

    public static func < (lhs: Dragon, rhs: Dragon) -> Bool { lhs.order < rhs.order }
}

/// Flower tiles come in two sets of four. Each flower in a set is associated with
/// a seat wind by index (1=E, 2=S, 3=W, 4=N). The "正花" bonus triggers when the
/// flower's index matches the player's seat wind.
public enum FlowerKind: String, CaseIterable, Codable, Sendable {
    case season  // 春夏秋冬
    case plant   // 梅蘭菊竹
}

public struct Flower: Hashable, Codable, Sendable, Comparable {
    public let kind: FlowerKind
    public let index: Int  // 1...4

    public init?(kind: FlowerKind, index: Int) {
        guard (1...4).contains(index) else { return nil }
        self.kind = kind
        self.index = index
    }

    /// The seat wind this flower corresponds to.
    public var seatWind: Wind {
        [.east, .south, .west, .north][index - 1]
    }

    public var displayName: String {
        let chars: [String] = switch kind {
        case .season: ["春", "夏", "秋", "冬"]
        case .plant:  ["梅", "蘭", "菊", "竹"]
        }
        return chars[index - 1]
    }

    public static func < (lhs: Flower, rhs: Flower) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .season }
        return lhs.index < rhs.index
    }
}

/// A mahjong tile. Parses from and serializes to a compact ASCII notation:
///
/// - `"1m"` ... `"9m"`        numbered characters (萬)
/// - `"1p"` ... `"9p"`        numbered dots (筒)
/// - `"1s"` ... `"9s"`        numbered bamboo (條)
/// - `"Ew"`, `"Sw"`, `"Ww"`, `"Nw"`   wind tiles
/// - `"Rd"`, `"Gd"`, `"Wd"`   dragon tiles (Red/Green/White)
/// - `"1f"` ... `"4f"`        season flowers (春/夏/秋/冬)
/// - `"5f"` ... `"8f"`        plant flowers (梅/蘭/菊/竹)
public enum Tile: Hashable, Sendable {
    case numeric(Suit, Int)  // rank in 1...9
    case wind(Wind)
    case dragon(Dragon)
    case flower(Flower)
}

// MARK: - Parsing

public extension Tile {
    enum ParseError: Error, Equatable {
        case empty
        case unknownFormat(String)
        case invalidRank(Int)
        case invalidFlowerIndex(Int)
    }

    /// Parse a tile from the ASCII notation above. Whitespace is trimmed.
    init(_ notation: String) throws {
        let s = notation.trimmingCharacters(in: .whitespaces)
        guard s.count == 2 else {
            if s.isEmpty { throw ParseError.empty }
            throw ParseError.unknownFormat(notation)
        }
        let first = s.first!
        let second = s.last!

        // Dragons: Rd / Gd / Wd
        if second == "d" {
            switch first {
            case "R": self = .dragon(.red); return
            case "G": self = .dragon(.green); return
            case "W": self = .dragon(.white); return
            default: throw ParseError.unknownFormat(notation)
            }
        }

        // Winds: Ew / Sw / Ww / Nw
        if second == "w" {
            guard let wind = Wind(rawValue: String(first)) else {
                throw ParseError.unknownFormat(notation)
            }
            self = .wind(wind); return
        }

        // Numeric or flower: digit then suit letter
        guard let digit = first.wholeNumberValue else {
            throw ParseError.unknownFormat(notation)
        }

        switch second {
        case "m", "p", "s":
            guard (1...9).contains(digit) else { throw ParseError.invalidRank(digit) }
            guard let suit = Suit(rawValue: String(second)) else {
                throw ParseError.unknownFormat(notation)
            }
            self = .numeric(suit, digit)
        case "f":
            guard (1...8).contains(digit) else { throw ParseError.invalidFlowerIndex(digit) }
            let kind: FlowerKind = digit <= 4 ? .season : .plant
            let index = digit <= 4 ? digit : digit - 4
            // Force-unwrap safe: index is 1...4 by construction.
            self = .flower(Flower(kind: kind, index: index)!)
        default:
            throw ParseError.unknownFormat(notation)
        }
    }
}

// MARK: - Serialization

public extension Tile {
    /// Round-trips with `init(_:)`.
    var notation: String {
        switch self {
        case .numeric(let suit, let rank):
            return "\(rank)\(suit.rawValue)"
        case .wind(let w):
            return "\(w.rawValue)w"
        case .dragon(let d):
            switch d {
            case .red: return "Rd"
            case .green: return "Gd"
            case .white: return "Wd"
            }
        case .flower(let f):
            let n = f.kind == .season ? f.index : f.index + 4
            return "\(n)f"
        }
    }

    var displayName: String {
        switch self {
        case .numeric(let suit, let rank): return "\(rank)\(suit.displayName)"
        case .wind(let w):    return w.displayName
        case .dragon(let d):  return d.displayName
        case .flower(let f):  return f.displayName
        }
    }

    /// Unicode glyph from the Mahjong Tiles block (U+1F000…U+1F02F).
    /// Suitable for UI display; renders as a filled tile in most fonts.
    var unicode: String {
        switch self {
        case .numeric(let suit, let rank):
            let base: UnicodeScalar = switch suit {
            case .man: "\u{1F007}"  // 🀇 (1m)
            case .pin: "\u{1F019}"  // 🀙 (1p)
            case .sou: "\u{1F010}"  // 🀐 (1s)
            }
            return String(UnicodeScalar(base.value + UInt32(rank - 1))!)
        case .wind(let w):
            let offset = w.seatIndex - 1   // E=0, S=1, W=2, N=3
            return String(UnicodeScalar(UInt32(0x1F000) + UInt32(offset))!)
        case .dragon(let d):
            switch d {
            case .red:   return "\u{1F004}"  // 🀄
            case .green: return "\u{1F005}"  // 🀅
            case .white: return "\u{1F006}"  // 🀆
            }
        case .flower(let f):
            let baseChar: UnicodeScalar = f.kind == .season ? "\u{1F022}" : "\u{1F026}"
            return String(UnicodeScalar(baseChar.value + UInt32(f.index - 1))!)
        }
    }
}

// MARK: - Categories & predicates

public extension Tile {
    var isHonor: Bool {
        switch self {
        case .wind, .dragon: true
        default: false
        }
    }

    var isFlower: Bool {
        if case .flower = self { return true } else { return false }
    }

    var isNumeric: Bool {
        if case .numeric = self { return true } else { return false }
    }

    /// Terminal = 1 or 9 of a numbered suit.
    var isTerminal: Bool {
        if case let .numeric(_, rank) = self { return rank == 1 || rank == 9 }
        return false
    }

    /// Simple = 2...8 of a numbered suit.
    var isSimple: Bool {
        if case let .numeric(_, rank) = self { return rank >= 2 && rank <= 8 }
        return false
    }
}

// MARK: - Comparable (canonical ordering)

extension Tile: Comparable {
    public static func < (lhs: Tile, rhs: Tile) -> Bool {
        func rank(_ t: Tile) -> (Int, Int, Int) {
            switch t {
            case .numeric(let s, let r): return (0, s < .pin ? 0 : (s < .sou ? 1 : 2), r)
            case .wind(let w):           return (1, w.seatIndex, 0)
            case .dragon(let d):
                let idx: Int = switch d { case .red: 0; case .green: 1; case .white: 2 }
                return (2, idx, 0)
            case .flower(let f):
                return (3, f.kind == .season ? 0 : 1, f.index)
            }
        }
        let a = rank(lhs), b = rank(rhs)
        if a.0 != b.0 { return a.0 < b.0 }
        if a.1 != b.1 { return a.1 < b.1 }
        return a.2 < b.2
    }
}

// MARK: - Codable

extension Tile: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        try self.init(s)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}

// MARK: - Full tile catalog

public extension Tile {
    /// The 34 distinct non-flower tile kinds (each normally has 4 physical copies).
    static let allNonFlowerKinds: [Tile] = {
        var out: [Tile] = []
        for suit in Suit.allCases {
            for rank in 1...9 { out.append(.numeric(suit, rank)) }
        }
        for w in Wind.allCases { out.append(.wind(w)) }
        for d in Dragon.allCases { out.append(.dragon(d)) }
        return out
    }()

    /// All 8 flower tiles.
    static let allFlowers: [Tile] = {
        var out: [Tile] = []
        for kind in FlowerKind.allCases {
            for i in 1...4 {
                out.append(.flower(Flower(kind: kind, index: i)!))
            }
        }
        return out
    }()
}
