import XCTest
@testable import MahjongCore

final class WaitInferenceTests: XCTestCase {

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
    private func kong(_ n: String, concealed: Bool = true) -> Meld {
        try! Meld(kind: .kong, tiles: Array(repeating: t(n), count: 4), isConcealed: concealed)
    }

    private func hand(melds: [Meld], eye: Meld, winningTile: Tile, winCompletes: WinCompletion) -> Hand {
        try! Hand(melds: melds, eye: eye, flowers: [],
                  winningTile: winningTile, winCompletes: winCompletes)
    }

    private lazy var stdMelds: [Meld] = [
        chow(["1m", "2m", "3m"]),
        chow(["4m", "5m", "6m"]),
        chow(["7p", "8p", "9p"]),
        chow(["1s", "2s", "3s"]),
        chow(["4s", "5s", "6s"]),
    ]

    // Eye completion

    func test_eyeCompletion_isSingleWait() {
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("Rd"), winCompletes: .eye)
        XCTAssertEqual(WaitInference.infer(for: h), .singleWait)
    }

    // Chow positions

    func test_chowMiddle_isClosedWait() {
        // Winning tile 5m completed the middle of 4m-5m-6m chow (position 1)
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("5m"), winCompletes: .meld(index: 1))
        XCTAssertEqual(WaitInference.infer(for: h), .closedWait)
    }

    func test_chow123_completedBy3_isEdgeWait() {
        // 1m-2m-3m, winning tile is the 3
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("3m"), winCompletes: .meld(index: 0))
        XCTAssertEqual(WaitInference.infer(for: h), .edgeWait)
    }

    func test_chow789_completedBy7_isEdgeWait() {
        // 7p-8p-9p, winning tile is the 7
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("7p"), winCompletes: .meld(index: 2))
        XCTAssertEqual(WaitInference.infer(for: h), .edgeWait)
    }

    func test_chow123_completedBy1_isOpenWait() {
        // 1m-2m-3m, winning tile is the 1 — NOT edge (edge requires 3 completion)
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("1m"), winCompletes: .meld(index: 0))
        XCTAssertEqual(WaitInference.infer(for: h), .openWait)
    }

    func test_chow456_completedBy6_isOpenWait() {
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("6m"), winCompletes: .meld(index: 1))
        XCTAssertEqual(WaitInference.infer(for: h), .openWait)
    }

    func test_chow456_completedBy4_isOpenWait() {
        let h = hand(melds: stdMelds, eye: pair("Rd"),
                     winningTile: t("4m"), winCompletes: .meld(index: 1))
        XCTAssertEqual(WaitInference.infer(for: h), .openWait)
    }

    // Pung / kong

    func test_pungCompletion_isPairWait() {
        var melds = stdMelds
        melds[0] = pung("5p")
        let h = hand(melds: melds, eye: pair("Rd"),
                     winningTile: t("5p"), winCompletes: .meld(index: 0))
        XCTAssertEqual(WaitInference.infer(for: h), .pairWait)
    }

    func test_kongCompletion_isPairWait() {
        var melds = stdMelds
        melds[0] = kong("5p")
        let h = hand(melds: melds, eye: pair("Rd"),
                     winningTile: t("5p"), winCompletes: .meld(index: 0))
        XCTAssertEqual(WaitInference.infer(for: h), .pairWait)
    }
}
