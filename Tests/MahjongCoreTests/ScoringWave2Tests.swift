import XCTest
@testable import MahjongCore

/// Wave 2 coverage: chow family, pung brackets, straights, outside hands,
/// structural patterns (五門齊 / 老少 / 缺一門), and new context awards.
final class ScoringWave2Tests: XCTestCase {

    // MARK: - Shared fixtures (mirrors ScoringTests for convenience)

    private lazy var scorer: Scorer = try! Scorer.loadDefault()

    private func t(_ s: String) -> Tile { try! Tile(s) }
    private func chow(_ n: [String], concealed: Bool = true) -> Meld {
        try! Meld(kind: .chow, tiles: n.map(t), isConcealed: concealed)
    }
    private func pung(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pung, tiles: Array(repeating: t(n), count: 3), isConcealed: concealed)
    }
    private func pair(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pair, tiles: Array(repeating: t(n), count: 2), isConcealed: concealed)
    }

    private func makeHand(
        melds: [Meld], eye: Meld, flowers: [Tile] = [],
        winningTile: Tile, winCompletes: WinCompletion
    ) -> Hand {
        try! Hand(melds: melds, eye: eye, flowers: flowers,
                  winningTile: winningTile, winCompletes: winCompletes)
    }

    private func ctx(
        selfDrawn: Bool = true,
        seatWind: Wind = .east,
        waitType: WaitType = .openWait,
        afterKong: Bool = false,
        afterKongOnKong: Bool = false,
        robbingKong: Bool = false,
        declaredTing: Bool = false,
        turnsBeforeWin: Int? = nil
    ) -> WinContext {
        WinContext(
            selfDrawn: selfDrawn, isDealer: false,
            roundWind: .east, seatWind: seatWind,
            waitType: waitType,
            afterKong: afterKong, afterKongOnKong: afterKongOnKong,
            robbingKong: robbingKong,
            declaredTing: declaredTing, turnsBeforeWin: turnsBeforeWin
        )
    }

    private func hasAward(_ breakdown: ScoreBreakdown, _ id: String) -> Bool {
        breakdown.awards.contains { $0.ruleId == id }
    }

    private func award(_ breakdown: ScoreBreakdown, _ id: String) -> TaiAward? {
        breakdown.awards.first { $0.ruleId == id }
    }

    // MARK: - Chow family

    func test_identicalChow_doublePair() {
        // 123m + 123m (identical) + 234p + 567s + 789s, eye 5p5p
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["1m", "2m", "3m"]),
                chow(["2p", "3p", "4p"]),
                chow(["5s", "6s", "7s"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "identical-chow"))
        XCTAssertEqual(award(br, "identical-chow")?.totalTai, 3)
    }

    func test_threeIdenticalChows() {
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["1m", "2m", "3m"]),
                chow(["1m", "2m", "3m"]),
                chow(["4p", "5p", "6p"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "three-identical-chows"))
        XCTAssertFalse(hasAward(br, "identical-chow"))
        XCTAssertEqual(award(br, "three-identical-chows")?.totalTai, 15)
    }

    func test_mixedTripleChow() {
        // 123 across all three suits → mixed-triple-chow (10)
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["1p", "2p", "3p"]),
                chow(["1s", "2s", "3s"]),
                chow(["4p", "5p", "6p"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "mixed-triple-chow"))
        XCTAssertEqual(award(br, "mixed-triple-chow")?.totalTai, 10)
        // Should NOT award mixed-double-chow for the same startRank group.
        // (Other startRanks with only one chow don't trigger it either.)
        XCTAssertFalse(hasAward(br, "mixed-double-chow"))
    }

    func test_fourSameChows_notIdentical() {
        // 2 × 123m + 123p + 123s → 4 chows at startRank 1. Max-identical is 2 (not 4)
        // so the four-same-chows (20) award fires instead of four-identical-chows (30).
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["1m", "2m", "3m"]),
                chow(["1p", "2p", "3p"]),
                chow(["1s", "2s", "3s"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5p"),
            winningTile: t("5p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "four-same-chows"))
        XCTAssertFalse(hasAward(br, "four-identical-chows"))
        XCTAssertEqual(award(br, "four-same-chows")?.totalTai, 20)
    }

    // MARK: - Pung brackets

    func test_bigThreeBrothers() {
        // 5m + 5p + 5s pungs → 3 pungs, 3 different suits, same rank.
        let hand = makeHand(
            melds: [
                pung("5m"),
                pung("5p"),
                pung("5s"),
                chow(["1m", "2m", "3m"]),
                chow(["7p", "8p", "9p"]),
            ],
            eye: pair("Rd"),
            winningTile: t("Rd"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "big-three-brothers"))
        XCTAssertEqual(award(br, "big-three-brothers")?.totalTai, 15)
        XCTAssertFalse(hasAward(br, "two-brothers"))
    }

    func test_smallThreeBrothers() {
        // 5m + 5p pungs + 5s eye → 2 pungs same rank in 2 suits, eye in 3rd suit same rank.
        let hand = makeHand(
            melds: [
                pung("5m"),
                pung("5p"),
                chow(["1m", "2m", "3m"]),
                chow(["7p", "8p", "9p"]),
                chow(["1s", "2s", "3s"]),
            ],
            eye: pair("5s"),
            winningTile: t("5s"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "small-three-brothers"))
        XCTAssertFalse(hasAward(br, "two-brothers"))
        XCTAssertEqual(award(br, "small-three-brothers")?.totalTai, 10)
    }

    func test_twoBrothers() {
        // 5m + 5p pungs, eye is Rd (not the same rank as the brothers).
        let hand = makeHand(
            melds: [
                pung("5m"),
                pung("5p"),
                chow(["1m", "2m", "3m"]),
                chow(["7p", "8p", "9p"]),
                chow(["4s", "5s", "6s"]),
            ],
            eye: pair("Rd"),
            winningTile: t("Rd"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "two-brothers"))
        XCTAssertEqual(award(br, "two-brothers")?.totalTai, 3)
        XCTAssertFalse(hasAward(br, "small-three-brothers"))
    }

    // MARK: - Straights

    func test_concealedPureStraight() {
        // 123p + 456p + 789p all concealed → concealed-pure-straight (20).
        let hand = makeHand(
            melds: [
                chow(["1p", "2p", "3p"]),
                chow(["4p", "5p", "6p"]),
                chow(["7p", "8p", "9p"]),
                chow(["1m", "2m", "3m"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5s"),
            winningTile: t("5s"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "concealed-pure-straight"))
        XCTAssertEqual(award(br, "concealed-pure-straight")?.totalTai, 20)
        // Mixed-straight should not also fire.
        XCTAssertFalse(hasAward(br, "concealed-mixed-straight"))
        XCTAssertFalse(hasAward(br, "exposed-mixed-straight"))
    }

    func test_exposedPureStraight() {
        // 123p + 456p + 789p where one chow is exposed → exposed-pure-straight (10).
        let hand = makeHand(
            melds: [
                chow(["1p", "2p", "3p"], concealed: false),
                chow(["4p", "5p", "6p"]),
                chow(["7p", "8p", "9p"]),
                chow(["1m", "2m", "3m"]),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("5s"),
            winningTile: t("5s"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx(selfDrawn: false))
        XCTAssertTrue(hasAward(br, "exposed-pure-straight"))
        XCTAssertEqual(award(br, "exposed-pure-straight")?.totalTai, 10)
        XCTAssertFalse(hasAward(br, "concealed-pure-straight"))
    }

    // MARK: - Outside hands

    func test_outsideHandPure() {
        // Every meld/eye contains a terminal (1 or 9); no honors.
        // 123m + 789m + 123p + 789s + 1s1s1s pung, eye 9p9p
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["7m", "8m", "9m"]),
                chow(["1p", "2p", "3p"]),
                chow(["7s", "8s", "9s"]),
                pung("1s"),
            ],
            eye: pair("9p"),
            winningTile: t("9p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "outside-hand-pure"))
        XCTAssertEqual(award(br, "outside-hand-pure")?.totalTai, 15)
        // all-terminals doesn't apply (has 2/3/7/8 etc).
        XCTAssertFalse(hasAward(br, "all-terminals"))
    }

    func test_outsideHandMixed_withHonors() {
        // Every meld/eye contains a terminal or honor; at least one honor exists.
        let hand = makeHand(
            melds: [
                chow(["1m", "2m", "3m"]),
                chow(["7m", "8m", "9m"]),
                pung("Ew"),           // honor meld
                pung("1s"),
                chow(["7s", "8s", "9s"]),
            ],
            eye: pair("9p"),
            winningTile: t("9p"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx())
        XCTAssertTrue(hasAward(br, "outside-hand-mixed"))
        XCTAssertEqual(award(br, "outside-hand-mixed")?.totalTai, 10)
        XCTAssertFalse(hasAward(br, "outside-hand-pure"))
    }

    // MARK: - Context awards

    func test_declaredReady_add5Tai() {
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
        let br = scorer.score(hand: hand, context: ctx(declaredTing: true))
        XCTAssertTrue(hasAward(br, "declared-ready"))
        XCTAssertEqual(award(br, "declared-ready")?.totalTai, 5)
    }

    func test_allClaimedDiscard() {
        // Every body meld exposed; won off a discard.
        let hand = makeHand(
            melds: [
                pung("1m", concealed: false),
                pung("5p", concealed: false),
                pung("9s", concealed: false),
                pung("Ew", concealed: false),
                pung("Rd", concealed: false),
            ],
            eye: pair("2s"),
            winningTile: t("1m"),
            winCompletes: .meld(index: 0)
        )
        let br = scorer.score(hand: hand, context: ctx(selfDrawn: false, waitType: .pairWait))
        XCTAssertTrue(hasAward(br, "all-claimed-discard"))
        XCTAssertEqual(award(br, "all-claimed-discard")?.totalTai, 15)
        // Should NOT get self-draw, concealed-hand, or all-claimed-self-draw.
        XCTAssertFalse(hasAward(br, "self-draw"))
        XCTAssertFalse(hasAward(br, "concealed-hand"))
        XCTAssertFalse(hasAward(br, "all-claimed-self-draw"))
    }

    func test_allClaimedSelfDraw() {
        let hand = makeHand(
            melds: [
                pung("1m", concealed: false),
                pung("5p", concealed: false),
                pung("9s", concealed: false),
                pung("Ew", concealed: false),
                pung("Rd", concealed: false),
            ],
            eye: pair("2s"),
            winningTile: t("2s"),
            winCompletes: .eye
        )
        let br = scorer.score(hand: hand, context: ctx(selfDrawn: true))
        XCTAssertTrue(hasAward(br, "all-claimed-self-draw"))
        XCTAssertEqual(award(br, "all-claimed-self-draw")?.totalTai, 8)
        XCTAssertFalse(hasAward(br, "self-draw"))
        XCTAssertFalse(hasAward(br, "all-claimed-discard"))
    }

    func test_winWithinSeven_supersedesWithinTen() {
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
        let br = scorer.score(hand: hand, context: ctx(turnsBeforeWin: 6))
        XCTAssertTrue(hasAward(br, "win-within-seven"))
        XCTAssertFalse(hasAward(br, "win-within-ten"))
        XCTAssertEqual(award(br, "win-within-seven")?.totalTai, 20)
    }

    func test_winWithinTen_boundary() {
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
        let br = scorer.score(hand: hand, context: ctx(turnsBeforeWin: 10))
        XCTAssertTrue(hasAward(br, "win-within-ten"))
        XCTAssertFalse(hasAward(br, "win-within-seven"))
    }

    func test_kongOnKongWin_supersedesWinOnKong() {
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
        let br = scorer.score(hand: hand, context: ctx(
            selfDrawn: true, afterKong: true, afterKongOnKong: true
        ))
        XCTAssertTrue(hasAward(br, "kong-on-kong-win"))
        XCTAssertEqual(award(br, "kong-on-kong-win")?.totalTai, 30)
        XCTAssertFalse(hasAward(br, "win-on-kong"))
    }

    func test_robbingKongOnKong_supersedesRobbing() {
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
        let br = scorer.score(hand: hand, context: ctx(
            selfDrawn: false, afterKongOnKong: true, robbingKong: true
        ))
        XCTAssertTrue(hasAward(br, "robbing-kong-on-kong"))
        XCTAssertFalse(hasAward(br, "robbing-a-kong"))
        XCTAssertFalse(hasAward(br, "win-on-kong"))
    }
}
