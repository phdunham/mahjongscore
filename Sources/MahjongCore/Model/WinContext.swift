import Foundation

/// How the winning tile was being waited on at the moment of the win.
/// Needed to distinguish tai-scoring waits (邊張 / 嵌張 / 單釣 / 對碰 / open).
public enum WaitType: String, CaseIterable, Codable, Sendable {
    case openWait     // 兩面 — standard two-sided chow wait (e.g. 34 waiting on 2 or 5)
    case closedWait   // 嵌張 — closed-chow middle wait (e.g. 13 waiting on 2)
    case edgeWait     // 邊張 — edge wait (12 waiting on 3, or 89 waiting on 7)
    case pairWait     // 對碰 — waiting on one of two pungs to complete
    case singleWait   // 單釣 — single-tile wait on the eye
}

/// Everything that isn't part of the hand's tile shape but still affects scoring:
/// seat/round winds, self-drawn vs. discard, and the various special circumstances
/// (海底, 槓上開花, 搶槓, 天胡 / 地胡 / 人胡).
public struct WinContext: Hashable, Codable, Sendable {
    // Core
    public var selfDrawn: Bool       // 自摸
    public var isDealer: Bool        // 莊家 (dealer, seat wind = east)
    public var roundWind: Wind       // 場風 (prevailing wind)
    public var seatWind: Wind        // 自風 (player's seat wind)
    public var waitType: WaitType

    // Special circumstances
    public var lastTile: Bool          // 海底撈月 — won on the last tile in the wall
    public var afterKong: Bool         // 槓上開花 — won on the replacement tile after a kong
    public var afterKongOnKong: Bool   // 摃上摃 — won on replacement after two kongs in a row
    public var afterFlower: Bool       // 花上食胡 — won on the replacement tile after a flower
    public var robbingKong: Bool       // 搶槓 — won off another player's added-kong tile
    public var heavenlyHand: Bool      // 天胡 — dealer wins on initial deal
    public var earthlyHand: Bool       // 地胡 — non-dealer wins on first draw
    public var humanHand: Bool         // 人胡 — non-dealer wins within first 4 tiles

    // Wave-2 additions
    public var declaredTing: Bool      // 聽牌 (叮) — player declared ready before winning
    public var turnsBeforeWin: Int?    // tiles drawn before the winning tile (for 十只內 / 七只內)

    public init(
        selfDrawn: Bool,
        isDealer: Bool,
        roundWind: Wind,
        seatWind: Wind,
        waitType: WaitType,
        lastTile: Bool = false,
        afterKong: Bool = false,
        afterKongOnKong: Bool = false,
        afterFlower: Bool = false,
        robbingKong: Bool = false,
        heavenlyHand: Bool = false,
        earthlyHand: Bool = false,
        humanHand: Bool = false,
        declaredTing: Bool = false,
        turnsBeforeWin: Int? = nil
    ) {
        self.selfDrawn = selfDrawn
        self.isDealer = isDealer
        self.roundWind = roundWind
        self.seatWind = seatWind
        self.waitType = waitType
        self.lastTile = lastTile
        self.afterKong = afterKong
        self.afterKongOnKong = afterKongOnKong
        self.afterFlower = afterFlower
        self.robbingKong = robbingKong
        self.heavenlyHand = heavenlyHand
        self.earthlyHand = earthlyHand
        self.humanHand = humanHand
        self.declaredTing = declaredTing
        self.turnsBeforeWin = turnsBeforeWin
    }
}
