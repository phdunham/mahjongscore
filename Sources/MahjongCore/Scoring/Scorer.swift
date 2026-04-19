import Foundation

/// Scores a winning `Hand` against a `WinContext` using the bundled rule table.
///
/// **Wave 1 coverage (~25 patterns):**
/// - Flower: no-flowers, wrong-flower, correct-flower, one-set-flowers, two-sets-flowers
/// - Bonus: self-draw, pair-wait, value-eye, single-edge-wait, concealed-hand,
///          concealed-self-draw, robbing-a-kong, win-on-flower, win-on-kong, last-tile-self-draw
/// - Set: exposed-kong, concealed-kong, all-pungs, two/three/four-concealed-pungs
/// - Suit: no-honors, all-chows, no-honors-no-flowers, half-flush, full-flush, great-pure-ping
/// - Dragon-Wind: pung-seat-wind, pung-other-wind, pung-dragon,
///                little-three-dragons, big-three-dragons,
///                little-three-winds, big-three-winds, little-four-winds, big-four-winds
/// - Terminal: all-simples, all-terminals-honors, all-terminals
/// - Special: heavenly-hand, earthly-hand, human-hand, five-concealed-pungs
///
/// **Deferred to Wave 2:** chow-family patterns (一般高 / 二相逢 / 三相逢 / 四同順 etc.),
/// bracketed pungs (二兄弟 / 三兄弟 etc.), 四歸X, 五門齊, 明/暗龍, 老少, 雞胡,
/// 七對 (嚦咕嚦咕), 十三幺, 十六不搭, 間間胡, 半求人 / 全求人, 聽牌, and 十只內 / 七只內.
public struct Scorer {
    public let rules: RuleTable

    public init(rules: RuleTable) { self.rules = rules }

    public static func loadDefault() throws -> Scorer {
        Scorer(rules: try RuleTable.load())
    }

    public func score(hand: Hand, context: WinContext) -> ScoreBreakdown {
        var awards: [TaiAward] = []
        awards += flowerAwards(hand: hand, context: context)
        awards += bonusAwards(hand: hand, context: context)
        awards += setAwards(hand: hand, context: context)
        awards += suitAwards(hand: hand, context: context)
        awards += dragonWindAwards(hand: hand, context: context)
        awards += terminalAwards(hand: hand, context: context)
        awards += specialAwards(hand: hand, context: context)
        awards += chowFamilyAwards(hand: hand, context: context)
        awards += pungBracketAwards(hand: hand, context: context)
        awards += straightAwards(hand: hand, context: context)
        awards += outsideHandAwards(hand: hand, context: context)
        awards += structuralAwards(hand: hand, context: context)
        return ScoreBreakdown(awards: awards)
    }
}
