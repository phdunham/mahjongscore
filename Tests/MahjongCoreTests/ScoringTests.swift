import XCTest
@testable import MahjongCore

final class ScoringTests: XCTestCase {

    // MARK: - Fixtures

    private lazy var scorer: Scorer = try! Scorer.loadDefault()

    private func t(_ s: String) -> Tile { try! Tile(s) }
    private func chow(_ n: [String], concealed: Bool = true) -> Meld {
        try! Meld(kind: .chow, tiles: n.map(t), isConcealed: concealed)
    }
    private func pung(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pung, tiles: Array(repeating: t(n), count: 3), isConcealed: concealed)
    }
    private func kong(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .kong, tiles: Array(repeating: t(n), count: 4), isConcealed: concealed)
    }
    private func pair(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pair, tiles: Array(repeating: t(n), count: 2), isConcealed: concealed)
    }

    private func ctx(
        selfDrawn: Bool = true,
        isDealer: Bool = false,
        roundWind: Wind = .east,
        seatWind: Wind = .east,
        waitType: WaitType = .openWait,
        lastTile: Bool = false,
        afterKong: Bool = false,
        afterFlower: Bool = false,
        robbingKong: Bool = false,
        heavenlyHand: Bool = false,
        earthlyHand: Bool = false,
        humanHand: Bool = false
    ) -> WinContext {
        WinContext(
            selfDrawn: selfDrawn, isDealer: isDealer,
            roundWind: roundWind, seatWind: seatWind,
            waitType: waitType,
            lastTile: lastTile, afterKong: afterKong, afterFlower: afterFlower,
            robbingKong: robbingKong,
            heavenlyHand: heavenlyHand, earthlyHand: earthlyHand, humanHand: humanHand
        )
    }

    private func makeHand(
        melds: [Meld], eye: Meld, flowers: [Tile] = [],
        winningTile: Tile, winCompletes: WinCompletion
    ) -> Hand {
        try! Hand(melds: melds, eye: eye, flowers: flowers,
                  winningTile: winningTile, winCompletes: winCompletes)
    }

    /// Assert the set of rule ids in the breakdown matches `expected` (order-agnostic)
    /// and each award's totalTai matches. `expected` pairs are (ruleId, totalTaiForThatAward).
    private func assertAwards(
        _ breakdown: ScoreBreakdown,
        _ expected: [(String, Int)],
        file: StaticString = #file, line: UInt = #line
    ) {
        let gotIds = Set(breakdown.awards.map(\.ruleId))
        let expectedIds = Set(expected.map(\.0))
        let got = breakdown.awards.map { "\($0.ruleId)(\($0.totalTai))" }.sorted()
        if gotIds != expectedIds {
            XCTFail("Award set mismatch. Expected: \(expectedIds.sorted()). Got: \(got)",
                    file: file, line: line)
            return
        }
        for (ruleId, expectedTotal) in expected {
            guard let award = breakdown.awards.first(where: { $0.ruleId == ruleId }) else {
                XCTFail("missing award \(ruleId)", file: file, line: line); continue
            }
            XCTAssertEqual(award.totalTai, expectedTotal,
                           "award \(ruleId) totalTai mismatch", file: file, line: line)
        }
        XCTAssertEqual(breakdown.totalTai, expected.reduce(0) { $0 + $1.1 },
                       "breakdown totalTai mismatch", file: file, line: line)
    }

    // MARK: - Rule table loads

    func test_ruleTable_loads() throws {
        let rt = try RuleTable.load()
        XCTAssertEqual(rt.patterns.count, 88)
        XCTAssertNotNil(rt.patterns.first(where: { $0.id == "self-draw" }))
    }

    // MARK: - Hand 1: great-pure-ping (multi-suit all-chows, no honors, no flowers, concealed self-draw)
    //
    //   melds  : 123m | 456m | 789p | 123s | 456s
    //   eye    : 3s3s  (rank 3 — NOT value-eye)
    //   flowers: none
    //   context: self-drawn, all concealed, open wait, east seat/round

    func test_greatPurePing_concealedSelfDraw() {
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["4m", "5m", "6m"]),
                chow(["7p", "8p", "9p"]),
                chow(["1s", "2s", "3s"]),
                chow(["4s", "5s", "6s"]),
            ],
            eye: pair("3s"),
            winningTile: t("3s"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, waitType: .singleWait
        ))
        // Eye is 3s (rank 3) → no value-eye.
        // great-pure-ping (10) subsumes all-chows + no-honors + no-honors-no-flowers.
        // Wave 2: chows at startRanks 1,4,7 across suits → concealed-mixed-straight (15).
        // startRank 1 (123m + 123s) and startRank 4 (456m + 456s) each give mixed-double-chow
        // → count=2, totalTai=4.
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("great-pure-ping", 10),
            ("concealed-mixed-straight", 15),
            ("mixed-double-chow", 4),
        ])
    }

    // MARK: - Hand 2: full-flush + all-chows (pure bamboo, 5 chows, concealed self-draw)
    //
    //   melds: 123s | 234s | 345s | 567s | 789s
    //   eye  : 9s9s  (rank 9 — NOT value-eye)

    func test_fullFlush_allChows() {
        let hand = makeHand(
            melds: [
                chow(["1s", "2s", "3s"]),
                chow(["2s", "3s", "4s"]),
                chow(["3s", "4s", "5s"]),
                chow(["5s", "6s", "7s"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("9s"),
            winningTile: t("9s"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, waitType: .singleWait
        ))
        // full-flush (80) + all-chows (3) — full-flush doesn't subsume 平胡.
        // Wave 2: 123s + 789s in same suit → old-young (2).
        // (No straight awards: 1,4,7 starts need startRank 4; this hand has 2,3,5,7 starts.)
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("full-flush", 80),
            ("all-chows", 3),
            ("old-young", 2),
        ])
    }

    // MARK: - Hand 3: all-pungs with concealed kong, 2 dragon pungs, 1 non-seat wind pung
    //
    //   melds   : 1m1m1m (exposed) | 5p5p5p5p (concealed kong) | NwNwNw (concealed)
    //             | RdRdRd (concealed) | GdGdGd (concealed)
    //   eye     : 2s2s (rank 2 → value-eye)
    //   flowers : none
    //   context : NOT self-drawn (win off discard), pair-wait, east seat/round, east seat
    //
    //   Concealed triplet-ish melds: 4 (5p kong + Nw pung + Rd pung + Gd pung).
    //   1m pung is exposed, so hand is NOT fully concealed, and five-concealed-pungs
    //   doesn't apply — four-concealed-pungs (30) does.

    func test_allPungs_withConcealedKong_andDragonPairwait() {
        let hand = makeHand(
            melds: [
                pung("1m", concealed: false),
                kong("5p"),
                pung("Nw"),
                pung("Rd"),
                pung("Gd"),
            ],
            eye: pair("2s"),
            winningTile: t("1m"),
            winCompletes: .meld(index: 0)
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: false, seatWind: .east, waitType: .pairWait
        ))
        // Nw is not east (seat or round) → pung-other-wind.
        // Wave 2: hand has m, p, s, winds, dragons → all-five-types (10).
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("pair-wait", 1),
            ("value-eye", 1),
            ("concealed-kong", 2),
            ("four-concealed-pungs", 30),
            ("all-pungs", 30),
            ("pung-dragon", 4),
            ("pung-other-wind", 1),
            ("all-five-types", 10),
        ])
    }

    // MARK: - Hand 4: big-three-dragons (3 dragon pungs + 2 chows + numeric eye)
    //
    //   melds: RdRdRd | GdGdGd | WdWdWd | 123m | 456m
    //   eye  : 5p5p (rank 5 → value-eye)

    func test_bigThreeDragons() {
        let hand = makeHand(
            melds: [
                pung("Rd"),
                pung("Gd"),
                pung("Wd"),
                chow(["1m", "2m", "3m"]),
                chow(["4m", "5m", "6m"]),
            ],
            eye: pair("5p"),
            winningTile: t("1m"),
            winCompletes: .meld(index: 3)
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, waitType: .edgeWait
        ))
        // big-three-dragons (40) supersedes pung-dragon ×3.
        // Two numeric suits (m, p) + honors → no full-flush / half-flush.
        // 3 concealed pungs → three-concealed-pungs (10).
        // Wave 2: only m + p numeric (missing s) → one-suit-missing (5).
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("value-eye", 1),
            ("big-three-dragons", 40),
            ("three-concealed-pungs", 10),
            ("one-suit-missing", 5),
        ])
    }

    // MARK: - Hand 5: little-three-dragons (2 dragon pungs + dragon eye)
    //
    //   melds: RdRdRd | GdGdGd | 123m | 456m | 789m
    //   eye  : WdWd (White dragon — NOT value-eye)

    func test_littleThreeDragons() {
        let hand = makeHand(
            melds: [
                pung("Rd"),
                pung("Gd"),
                chow(["1m", "2m", "3m"]),
                chow(["4m", "5m", "6m"]),
                chow(["7m", "8m", "9m"]),
            ],
            eye: pair("Wd"),
            winningTile: t("Wd"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, waitType: .singleWait
        ))
        // Mostly man + honors → half-flush (30). Only 3 chows (not all 5), so no 平胡.
        // 2 concealed dragon pungs → two-concealed-pungs (3).
        // Wave 2: 123m + 456m + 789m pure straight, all concealed → concealed-pure-straight (20).
        //         123m + 789m in same suit → old-young (2).
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("little-three-dragons", 20),
            ("half-flush", 30),
            ("two-concealed-pungs", 3),
            ("concealed-pure-straight", 20),
            ("old-young", 2),
        ])
    }

    // MARK: - Hand 6: flowers — 2 correct + 1 wrong + one-set not complete
    //
    //   Seat wind = south (index 2). Flowers 2f (summer), 6f (orchid → index 2)
    //   both match seat. 1f (spring, index 1) doesn't.

    func test_flowers_correctAndWrong() {
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)   // seat east
        let summer = Tile.flower(Flower(kind: .season, index: 2)!)   // seat south
        let orchid = Tile.flower(Flower(kind: .plant, index: 2)!)    // seat south
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["4m", "5m", "6m"]),
                chow(["7p", "8p", "9p"]),
                chow(["1s", "2s", "3s"]),
                chow(["4s", "5s", "6s"]),
            ],
            eye: pair("5s"),
            flowers: [spring, summer, orchid],
            winningTile: t("5s"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, seatWind: .south, waitType: .singleWait
        ))
        // eye 5s → value-eye.
        // Flowers: 2 correct (summer, orchid), 1 wrong (spring).
        // Not great-pure-ping (has flowers). all-chows (3), no-honors (1), no-honors-no-flowers NOT (flowers present).
        // Wave 2: chows 1,4,7 across suits concealed → concealed-mixed-straight (15).
        //         startRanks 1 and 4 each have 2 chows in 2 different suits → mixed-double-chow ×2 = 4.
        assertAwards(breakdown, [
            ("correct-flower", 4),
            ("wrong-flower", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("value-eye", 1),
            ("no-honors", 1),
            ("all-chows", 3),
            ("concealed-mixed-straight", 15),
            ("mixed-double-chow", 4),
        ])
    }

    // MARK: - Hand 7: all-simples (斷么) — no terminals, no honors

    func test_allSimples() {
        let hand = makeHand(
            melds: [
                chow(["2m", "3m", "4m"]),
                chow(["5m", "6m", "7m"]),
                pung("3p"),
                chow(["5s", "6s", "7s"]),
                chow(["6s", "7s", "8s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, waitType: .singleWait
        ))
        // Multi-suit, no honors, has 1 pung so not all-chows. no-honors-no-flowers applies.
        // Wave 2: chows at startRank 5 are 567m + 567s (2 suits) → mixed-double-chow (2).
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("value-eye", 1),
            ("no-honors", 1),
            ("no-honors-no-flowers", 5),
            ("all-simples", 5),
            ("mixed-double-chow", 2),
        ])
    }

    // MARK: - Hand 8: seat-wind pung + round-wind pung
    //
    //   melds: EwEwEw (seat=east & round=east → seat-wind pung)
    //          SwSwSw (not seat, not round → other-wind)
    //          123m | 456p | 789s
    //   eye  : 5s5s

    func test_windPungs_seatAndOther() {
        let hand = makeHand(
            melds: [
                pung("Ew"),
                pung("Sw"),
                chow(["1m", "2m", "3m"]),
                chow(["4p", "5p", "6p"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5s"),
            winningTile: t("5s"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, roundWind: .east, seatWind: .east, waitType: .singleWait
        ))
        // Two concealed wind pungs → two-concealed-pungs (3).
        // Wave 2: 123m + 456p + 789s concealed → concealed-mixed-straight (15).
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("concealed-self-draw", 5),
            ("single-edge-wait", 2),
            ("value-eye", 1),
            ("pung-seat-wind", 2),
            ("pung-other-wind", 1),
            ("two-concealed-pungs", 3),
            ("concealed-mixed-straight", 15),
        ])
    }

    // MARK: - Hand 9: discard win, exposed melds (concealed-hand does NOT apply)

    func test_exposedHand_discardWin_bareBones() {
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"], concealed: false),
                chow(["4m", "5m", "6m"]),
                chow(["7p", "8p", "9p"]),
                chow(["1s", "2s", "3s"]),
                chow(["4s", "5s", "6s"]),
            ],
            eye: pair("3s"),
            winningTile: t("3s"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: false, waitType: .openWait
        ))
        // Discard win, partially concealed → no self-draw / no concealed-hand / no wait bonus.
        // Multi-suit all chows + no honors + no flowers → great-pure-ping.
        // Wave 2: 1,4,7 starts across suits; first chow (1m) is exposed → exposed-mixed-straight (8).
        //         startRanks 1 (123m + 123s) and 4 (456m + 456s) → mixed-double-chow ×2 = 4.
        assertAwards(breakdown, [
            ("no-flowers", 1),
            ("great-pure-ping", 10),
            ("exposed-mixed-straight", 8),
            ("mixed-double-chow", 4),
        ])
    }

    // MARK: - Hand 10: special — heavenly hand flag set

    func test_heavenlyHand_flag() {
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["4m", "5m", "6m"]),
                chow(["7p", "8p", "9p"]),
                chow(["1s", "2s", "3s"]),
                chow(["4s", "5s", "6s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let breakdown = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, isDealer: true, waitType: .singleWait, heavenlyHand: true
        ))
        // Heavenly hand (100) stacks with the structure awards in this Wave 1.
        XCTAssertTrue(breakdown.awards.contains(where: { $0.ruleId == "heavenly-hand" }))
        let heavenly = breakdown.awards.first { $0.ruleId == "heavenly-hand" }!
        XCTAssertEqual(heavenly.totalTai, 100)
    }
}
