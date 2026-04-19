import XCTest
@testable import MahjongCore

final class HandTests: XCTestCase {

    // MARK: - Helpers

    private func t(_ s: String) -> Tile { try! Tile(s) }

    private func chow(_ notations: [String], concealed: Bool = true) -> Meld {
        try! Meld(kind: .chow, tiles: notations.map(t), isConcealed: concealed)
    }
    private func pung(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pung, tiles: [t(n), t(n), t(n)], isConcealed: concealed)
    }
    private func kong(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .kong, tiles: [t(n), t(n), t(n), t(n)], isConcealed: concealed)
    }
    private func pair(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .pair, tiles: [t(n), t(n)], isConcealed: concealed)
    }

    /// A syntactically valid concealed 5-meld hand to serve as a base for negative tests.
    private func baseMelds() -> [Meld] {
        [
            chow(["1m", "2m", "3m"]),
            chow(["4m", "5m", "6m"]),
            pung("5p"),
            pung("9s"),
            pung("Ew"),
        ]
    }

    // MARK: - Valid construction

    func test_validHand_meldWin() throws {
        let melds = baseMelds()
        let hand = try Hand(
            melds: melds,
            eye: pair("Rd"),
            flowers: [],
            winningTile: t("5p"),
            winCompletes: .meld(index: 2)
        )
        XCTAssertEqual(hand.chows.count, 2)
        XCTAssertEqual(hand.pungs.count, 3)
        XCTAssertEqual(hand.kongs.count, 0)
        XCTAssertTrue(hand.isFullyConcealed)
        XCTAssertEqual(hand.completedGroup, melds[2])
    }

    func test_validHand_eyeWin() throws {
        let hand = try Hand(
            melds: baseMelds(),
            eye: pair("Rd"),
            winningTile: t("Rd"),
            winCompletes: .eye
        )
        XCTAssertEqual(hand.completedGroup.kind, .pair)
    }

    func test_validHand_withFlowersAndKong() throws {
        let melds: [Meld] = [
            chow(["1m", "2m", "3m"]),
            chow(["4m", "5m", "6m"]),
            pung("5p"),
            kong("9s"),
            pung("Ew"),
        ]
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)
        let plum = Tile.flower(Flower(kind: .plant, index: 1)!)
        let hand = try Hand(
            melds: melds,
            eye: pair("Rd"),
            flowers: [spring, plum],
            winningTile: t("5p"),
            winCompletes: .meld(index: 2)
        )
        XCTAssertEqual(hand.kongs.count, 1)
        XCTAssertEqual(hand.flowers.count, 2)
        // Total body tiles: 4 chow + 4 chow... wait: 2 chows (6) + 2 pungs (6) + 1 kong (4) + eye (2) = 18
        XCTAssertEqual(hand.allBodyTiles.count, 18)
    }

    // MARK: - Structure violations

    func test_wrongMeldCount_throws() {
        let too_few = Array(baseMelds().dropLast())
        XCTAssertThrowsError(
            try Hand(melds: too_few, eye: pair("Rd"), winningTile: t("1m"), winCompletes: .meld(index: 0))
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .wrongMeldCount(got: 4)) }
    }

    func test_bodyMeldIsPair_throws() {
        var melds = baseMelds()
        melds[0] = pair("1m")
        XCTAssertThrowsError(
            try Hand(melds: melds, eye: pair("Rd"), winningTile: t("Rd"), winCompletes: .eye)
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .bodyMeldIsPair) }
    }

    func test_eyeNotPair_throws() {
        let eye = pung("Rd")  // a pung, not a pair
        XCTAssertThrowsError(
            try Hand(melds: baseMelds(), eye: eye, winningTile: t("1m"), winCompletes: .meld(index: 0))
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .eyeNotPair) }
    }

    // MARK: - Flowers

    func test_nonFlowerInFlowersList_throws() {
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                flowers: [t("1m")],
                winningTile: t("1m"),
                winCompletes: .meld(index: 0)
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .nonFlowerInFlowerList) }
    }

    func test_duplicateFlowers_throws() {
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                flowers: [spring, spring],
                winningTile: t("1m"),
                winCompletes: .meld(index: 0)
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .duplicateFlowers) }
    }

    func test_tooManyFlowers_throws() {
        let nine = Array(repeating: Tile.flower(Flower(kind: .season, index: 1)!), count: 9)
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                flowers: nine,
                winningTile: t("1m"),
                winCompletes: .meld(index: 0)
            )
        ) { error in
            // 9 is both >8 AND contains duplicates; tooManyFlowers is checked first.
            XCTAssertEqual(error as? Hand.ValidationError, .tooManyFlowers(got: 9))
        }
    }

    // MARK: - Winning tile

    func test_winningTileIsFlower_throws() {
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                winningTile: spring,
                winCompletes: .meld(index: 0)
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .winningTileIsFlower) }
    }

    func test_winCompletionIndexOutOfRange_throws() {
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                winningTile: t("1m"),
                winCompletes: .meld(index: 99)
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .winCompletionIndexOutOfRange) }
    }

    func test_winningTileNotInMeld_throws() {
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                winningTile: t("9m"),  // not part of melds[0] which is 1m-2m-3m
                winCompletes: .meld(index: 0)
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .winningTileNotInCompletedGroup) }
    }

    func test_winningTileNotInEye_throws() {
        XCTAssertThrowsError(
            try Hand(
                melds: baseMelds(),
                eye: pair("Rd"),
                winningTile: t("Gd"),
                winCompletes: .eye
            )
        ) { XCTAssertEqual($0 as? Hand.ValidationError, .winningTileNotInCompletedGroup) }
    }

    // MARK: - Derived properties

    func test_isFullyConcealed_falseWhenAnyMeldExposed() throws {
        var melds = baseMelds()
        melds[0] = chow(["1m", "2m", "3m"], concealed: false)
        let hand = try Hand(
            melds: melds,
            eye: pair("Rd"),
            winningTile: t("Rd"),
            winCompletes: .eye
        )
        XCTAssertFalse(hand.isFullyConcealed)
    }

    func test_isFullyConcealed_falseWhenEyeExposed() throws {
        // An exposed eye is unusual but we still honor the flag.
        let hand = try Hand(
            melds: baseMelds(),
            eye: pair("Rd", concealed: false),
            winningTile: t("Rd"),
            winCompletes: .eye
        )
        XCTAssertFalse(hand.isFullyConcealed)
    }

    // MARK: - Codable

    func test_hand_codable_roundTrip() throws {
        let original = try Hand(
            melds: baseMelds(),
            eye: pair("Rd"),
            flowers: [Tile.flower(Flower(kind: .season, index: 2)!)],
            winningTile: t("Ew"),
            winCompletes: .meld(index: 4)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Hand.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - WinContext smoke

    func test_winContext_codable_roundTrip() throws {
        let ctx = WinContext(
            selfDrawn: true,
            isDealer: false,
            roundWind: .east,
            seatWind: .south,
            waitType: .singleWait,
            lastTile: true
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(WinContext.self, from: data)
        XCTAssertEqual(decoded, ctx)
        XCTAssertFalse(decoded.robbingKong)  // default
    }
}
