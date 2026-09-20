import Foundation
import MahjongCore

/// A tile with a stable identity, so duplicates (a pung of 5p) can still be
/// individually selected, removed, or marked as the winning tile.
public struct EntryTile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var tile: Tile

    public init(_ tile: Tile, id: UUID = UUID()) {
        self.id = id
        self.tile = tile
    }
}

/// Which body row a grid tap appends to.
public enum HandSection: String, CaseIterable, Identifiable, Sendable {
    case concealed
    case exposed

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .concealed: "Concealed"
        case .exposed: "Exposed"
        }
    }
}

/// State for tap-to-enter hand scoring. Shared by the macOS and iOS UIs.
///
/// Entry rules:
/// - Flowers always go to the flowers row (never a body row) and are
///   deduplicated — there is exactly one physical copy of each flower.
/// - Body tiles cap at 4 copies per kind.
/// - The most recently added body tile is the winning tile until the user
///   marks one explicitly (players naturally enter the winning tile last).
@MainActor
public final class HandEntryModel: ObservableObject {

    // MARK: Hand

    @Published public private(set) var concealed: [EntryTile] = []
    @Published public private(set) var exposed: [EntryTile] = []
    @Published public private(set) var flowers: [EntryTile] = []
    @Published public private(set) var winningId: UUID?
    @Published public var selectedId: UUID?
    @Published public var target: HandSection = .concealed

    /// Haptic triggers. They advance only when an action really changed the
    /// hand, so a tap that does nothing (tile already at its limit, nothing to
    /// undo) stays silent.
    @Published public private(set) var tileAddCount = 0
    @Published public private(set) var editCount = 0

    /// Insertion order, for undo.
    private var history: [UUID] = []
    private var winningIsAuto = true

    // MARK: Win context (persisted fields save on change)

    @Published public var selfDrawn = true
    @Published public var isDealer: Bool { didSet { defaults.set(isDealer, forKey: Keys.isDealer) } }
    @Published public var roundWind: Wind { didSet { defaults.set(roundWind.rawValue, forKey: Keys.roundWind) } }
    @Published public var seatWind: Wind { didSet { defaults.set(seatWind.rawValue, forKey: Keys.seatWind) } }
    @Published public var taiBase: Int { didSet { defaults.set(taiBase, forKey: Keys.taiBase) } }
    /// On by default: at this table nearly every win is declared ready first.
    @Published public var declaredTing = true
    @Published public var lastTile = false
    @Published public var afterKong = false
    @Published public var afterKongOnKong = false
    @Published public var afterFlower = false
    @Published public var robbingKong = false
    @Published public var heavenlyHand = false
    @Published public var earthlyHand = false
    @Published public var humanHand = false
    @Published public var turnsBeforeWin: String = ""

    // MARK: Result

    @Published public private(set) var breakdown: ScoreBreakdown?
    @Published public private(set) var inferredWait: WaitType?
    @Published public private(set) var scoreError: String?

    private let defaults: UserDefaults
    private lazy var scorer: Scorer? = try? Scorer.loadDefault()

    private enum Keys {
        static let isDealer = "taiIsDealer"
        static let roundWind = "roundWindRaw"
        static let seatWind = "seatWindRaw"
        static let taiBase = "taiBase"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDealer = defaults.bool(forKey: Keys.isDealer)
        roundWind = Wind(rawValue: defaults.string(forKey: Keys.roundWind) ?? "") ?? .east
        seatWind = Wind(rawValue: defaults.string(forKey: Keys.seatWind) ?? "") ?? .east
        taiBase = defaults.object(forKey: Keys.taiBase) as? Int ?? 5
    }

    // MARK: Derived

    public var bodyTiles: [EntryTile] { concealed + exposed }
    public var bodyCount: Int { concealed.count + exposed.count }
    public var isEmpty: Bool { bodyCount == 0 && flowers.isEmpty }
    public var canUndo: Bool { !history.isEmpty }

    public var selected: EntryTile? {
        guard let id = selectedId else { return nil }
        return (bodyTiles + flowers).first { $0.id == id }
    }

    public var selectedIsFlower: Bool { selected?.tile.isFlower ?? false }
    public var selectedIsWinning: Bool { selectedId != nil && selectedId == winningId }

    public var selectedSection: HandSection? {
        guard let id = selectedId else { return nil }
        if concealed.contains(where: { $0.id == id }) { return .concealed }
        if exposed.contains(where: { $0.id == id }) { return .exposed }
        return nil
    }

    public func usedCount(of tile: Tile) -> Int {
        if tile.isFlower { return flowers.contains { $0.tile == tile } ? 1 : 0 }
        return bodyTiles.reduce(0) { $0 + ($1.tile == tile ? 1 : 0) }
    }

    public func canAdd(_ tile: Tile) -> Bool {
        tile.isFlower ? usedCount(of: tile) == 0 : usedCount(of: tile) < 4
    }

    // MARK: Mutation

    public func add(_ tile: Tile) {
        guard canAdd(tile) else { return }
        let entry = EntryTile(tile)
        if tile.isFlower {
            flowers.append(entry)
        } else {
            switch target {
            case .concealed: concealed.append(entry)
            case .exposed: exposed.append(entry)
            }
            if winningIsAuto { winningId = entry.id }
        }
        history.append(entry.id)
        selectedId = nil
        tileAddCount += 1
        clearResult()
    }

    public func undo() {
        guard let id = history.last else { return }
        remove(id: id)
    }

    public func remove(id: UUID) {
        guard (bodyTiles + flowers).contains(where: { $0.id == id }) else { return }
        editCount += 1
        concealed.removeAll { $0.id == id }
        exposed.removeAll { $0.id == id }
        flowers.removeAll { $0.id == id }
        history.removeAll { $0 == id }
        if selectedId == id { selectedId = nil }
        if winningId == id {
            winningId = nil
            winningIsAuto = true
        }
        if winningIsAuto {
            winningId = history.last { hid in bodyTiles.contains { $0.id == hid } }
        }
        clearResult()
    }

    public func removeSelected() {
        guard let id = selectedId else { return }
        remove(id: id)
    }

    public func toggleWinning(id: UUID) {
        guard bodyTiles.contains(where: { $0.id == id }) else { return }
        winningIsAuto = false
        winningId = (winningId == id) ? nil : id
        editCount += 1
        clearResult()
    }

    public func toggleWinningSelected() {
        guard let id = selectedId else { return }
        toggleWinning(id: id)
    }

    /// Move the selected body tile to the other row.
    public func moveSelectedToOtherSection() {
        guard let id = selectedId else { return }
        if let i = concealed.firstIndex(where: { $0.id == id }) {
            exposed.append(concealed.remove(at: i))
        } else if let i = exposed.firstIndex(where: { $0.id == id }) {
            concealed.append(exposed.remove(at: i))
        } else {
            return
        }
        editCount += 1
        clearResult()
    }

    public func clearHand() {
        if !isEmpty { editCount += 1 }
        concealed = []
        exposed = []
        flowers = []
        history = []
        winningId = nil
        winningIsAuto = true
        selectedId = nil
        target = .concealed
        selfDrawn = true
        declaredTing = true
        lastTile = false
        afterKong = false
        afterKongOnKong = false
        afterFlower = false
        robbingKong = false
        heavenlyHand = false
        earthlyHand = false
        humanHand = false
        turnsBeforeWin = ""
        clearResult()
    }

    private func clearResult() {
        breakdown = nil
        inferredWait = nil
        scoreError = nil
    }

    /// Tai value of a rule from Rules.json, for showing "+N" beside a toggle.
    public func tai(forRule id: String) -> Int? {
        scorer?.rules.patterns.first { $0.id == id }?.tai
    }

    // MARK: Scoring

    public func score() {
        clearResult()
        guard let scorer else {
            scoreError = "Rules failed to load."
            return
        }
        let c = concealed.map(\.tile)
        let e = exposed.map(\.tile)
        let f = flowers.map(\.tile)
        guard let wid = winningId,
              let winning = bodyTiles.first(where: { $0.id == wid })?.tile
        else {
            scoreError = "Tap a tile in the hand and mark it as the winning tile."
            return
        }
        do {
            let hand = try Decomposer.decomposeWithConcealment(
                concealedTiles: c, exposedTiles: e, flowers: f, winningTile: winning
            )
            let wait = WaitInference.infer(for: hand)
            inferredWait = wait
            let ctx = WinContext(
                selfDrawn: selfDrawn,
                isDealer: isDealer,
                roundWind: roundWind,
                seatWind: seatWind,
                waitType: wait,
                lastTile: lastTile,
                afterKong: afterKong,
                afterKongOnKong: afterKongOnKong,
                afterFlower: afterFlower,
                robbingKong: robbingKong,
                heavenlyHand: heavenlyHand,
                earthlyHand: earthlyHand,
                humanHand: humanHand,
                declaredTing: declaredTing,
                turnsBeforeWin: Int(turnsBeforeWin.trimmingCharacters(in: .whitespaces))
            )
            breakdown = scorer.score(hand: hand, context: ctx)
        } catch {
            let n = c.count + e.count
            if n < 17 {
                // 17 is the minimum: five melds of three, a pair, no kongs.
                scoreError = "A winning hand has at least 17 tiles (5 sets and a pair). You've entered \(n)."
            } else {
                scoreError = "These \(n) tiles don't split into 5 sets and a pair. Check for a wrong or missing tile."
            }
        }
    }
}
