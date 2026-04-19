import XCTest
@testable import MahjongCore

final class DecomposerTests: XCTestCase {

    private func t(_ s: String) -> Tile { try! Tile(s) }

    func test_allChows_decomposes() throws {
        // 123m 456m 789p 123s 456s + eye 3s3s = 17 tiles
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7p","8p","9p",
            "1s","2s","3s", "4s","5s","6s", "3s","3s",
        ].map(t)
        let hand = try Decomposer.decompose(
            bodyTiles: tiles, winningTile: t("3s")
        )
        XCTAssertEqual(hand.melds.count, 5)
        XCTAssertTrue(hand.chows.count == 5)
        XCTAssertEqual(hand.eye.baseTile, t("3s"))
    }

    func test_withKong_expands17To18Tiles() throws {
        // 123m 456m 789p 5s5s5s5s (kong) 7s8s9s + eye 2s2s = 18 tiles
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7p","8p","9p",
            "5s","5s","5s","5s", "7s","8s","9s", "2s","2s",
        ].map(t)
        let hand = try Decomposer.decompose(
            bodyTiles: tiles, winningTile: t("2s")
        )
        XCTAssertEqual(hand.kongs.count, 1)
        XCTAssertEqual(hand.eye.baseTile, t("2s"))
    }

    func test_allPungs_decomposes() throws {
        // 1m pung, 5p pung, 9s pung, Ew pung, Rd pung + eye 2s2s
        let tiles = [
            "1m","1m","1m", "5p","5p","5p", "9s","9s","9s",
            "Ew","Ew","Ew", "Rd","Rd","Rd", "2s","2s",
        ].map(t)
        let hand = try Decomposer.decompose(
            bodyTiles: tiles, winningTile: t("1m")
        )
        XCTAssertEqual(hand.pungs.count, 5)
        XCTAssertTrue(hand.chows.isEmpty)
    }

    func test_winningTile_canCompleteEye() throws {
        // Wd is the eye; 2 copies present
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7m","8m","9m",
            "Rd","Rd","Rd", "Gd","Gd","Gd", "Wd","Wd",
        ].map(t)
        let hand = try Decomposer.decompose(
            bodyTiles: tiles, winningTile: t("Wd")
        )
        if case .eye = hand.winCompletes {
            // ok
        } else {
            XCTFail("expected winCompletes == .eye; got \(hand.winCompletes)")
        }
    }

    func test_wrongTileCount_throws() {
        let tiles: [Tile] = []
        XCTAssertThrowsError(
            try Decomposer.decompose(bodyTiles: tiles, winningTile: t("1m"))
        ) { error in
            XCTAssertEqual(error as? Decomposer.DecomposeError, .wrongTileCount(got: 0))
        }
    }

    func test_winningTileNotInTiles_throws() {
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7p","8p","9p",
            "1s","2s","3s", "4s","5s","6s", "3s","3s",
        ].map(t)
        XCTAssertThrowsError(
            try Decomposer.decompose(bodyTiles: tiles, winningTile: t("Rd"))
        ) { error in
            XCTAssertEqual(error as? Decomposer.DecomposeError, .noValidDecomposition)
        }
    }

    func test_unstructurableHand_throws() {
        // 17 random tiles that can't form 5 melds + eye
        let tiles = [
            "1m","2m","4m", "5m","7m","9p", "2p","3p","8p",
            "1s","3s","7s", "9s","Ew","Sw", "Rd","Wd",
        ].map(t)
        XCTAssertThrowsError(
            try Decomposer.decompose(bodyTiles: tiles, winningTile: t("1m"))
        ) { error in
            XCTAssertEqual(error as? Decomposer.DecomposeError, .noValidDecomposition)
        }
    }

    func test_scoreEndToEnd_fromDecomposedHand() throws {
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7p","8p","9p",
            "1s","2s","3s", "4s","5s","6s", "3s","3s",
        ].map(t)
        let hand = try Decomposer.decompose(
            bodyTiles: tiles, winningTile: t("3s")
        )
        let scorer = try Scorer.loadDefault()
        let ctx = WinContext(
            selfDrawn: true, isDealer: false,
            roundWind: .east, seatWind: .east,
            waitType: .singleWait
        )
        let breakdown = scorer.score(hand: hand, context: ctx)
        XCTAssertGreaterThan(breakdown.totalTai, 0)
        XCTAssertTrue(breakdown.awards.contains { $0.ruleId == "great-pure-ping" })
    }
}
