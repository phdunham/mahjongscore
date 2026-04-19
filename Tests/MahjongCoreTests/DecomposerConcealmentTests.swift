import XCTest
@testable import MahjongCore

final class DecomposerConcealmentTests: XCTestCase {

    private func t(_ s: String) -> Tile { try! Tile(s) }

    func test_concealedAndExposed_producesCorrectConcealmentPerMeld() throws {
        // Upper (concealed): 123m 456m 789p 3s3s (2 chows + eye), winning tile 3s
        // Lower (exposed):   5p 5p 5p 9s 9s 9s (2 pungs)
        let hand = try Decomposer.decomposeWithConcealment(
            concealedTiles: [
                t("1m"), t("2m"), t("3m"),
                t("4m"), t("5m"), t("6m"),
                t("7p"), t("8p"), t("9p"),
                t("3s"), t("3s"),
            ],
            exposedTiles: [
                t("5p"), t("5p"), t("5p"),
                t("9s"), t("9s"), t("9s"),
            ],
            winningTile: t("3s")
        )
        // Three concealed melds (the chows) + two exposed pungs + eye.
        let concealedMelds = hand.melds.filter(\.isConcealed)
        let exposedMelds = hand.melds.filter { !$0.isConcealed }
        XCTAssertEqual(concealedMelds.count, 3)
        XCTAssertEqual(exposedMelds.count, 2)
        XCTAssertTrue(exposedMelds.allSatisfy { $0.kind == .pung })
        XCTAssertTrue(hand.eye.isConcealed)
        XCTAssertFalse(hand.isFullyConcealed)
    }

    func test_emptyExposed_matchesLegacyDecompose() throws {
        let tiles = [
            "1m","2m","3m", "4m","5m","6m", "7p","8p","9p",
            "1s","2s","3s", "4s","5s","6s", "3s","3s",
        ].map(t)
        let handA = try Decomposer.decompose(bodyTiles: tiles, winningTile: t("3s"))
        let handB = try Decomposer.decomposeWithConcealment(
            concealedTiles: tiles, exposedTiles: [], winningTile: t("3s")
        )
        XCTAssertEqual(handA.melds.count, handB.melds.count)
        XCTAssertTrue(handB.isFullyConcealed)
    }

    func test_exposedTilesNotFormingValidMelds_throws() {
        // 5p 5p + random tiles — can't partition into chow/pung/kong cleanly
        XCTAssertThrowsError(
            try Decomposer.decomposeWithConcealment(
                concealedTiles: [t("1m"), t("2m")],
                exposedTiles: [t("5p"), t("5p"), t("7s")],
                winningTile: t("1m")
            )
        )
    }

    func test_winningTileInExposedMeld() throws {
        // Concealed: 3 chows + eye (11 tiles)
        // Exposed:   2 pungs including the winning tile's pung
        let hand = try Decomposer.decomposeWithConcealment(
            concealedTiles: [
                t("1m"), t("2m"), t("3m"),
                t("4m"), t("5m"), t("6m"),
                t("7p"), t("8p"), t("9p"),
                t("3s"), t("3s"),
            ],
            exposedTiles: [
                t("5p"), t("5p"), t("5p"),
                t("9s"), t("9s"), t("9s"),
            ],
            winningTile: t("5p")
        )
        // Winning tile is 5p, which is in an exposed pung
        switch hand.winCompletes {
        case .meld(let i):
            XCTAssertFalse(hand.melds[i].isConcealed)
            XCTAssertEqual(hand.melds[i].kind, .pung)
        case .eye:
            XCTFail("expected winCompletes to be a meld")
        }
    }
}
