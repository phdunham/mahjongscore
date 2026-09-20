import XCTest
import MahjongCore
@testable import MahjongUI

/// Which switches start on, and which survive Clear. These defaults are set to
/// match how this table actually plays, so they're easy to change by accident
/// and worth pinning down.
@MainActor
final class HandEntryModelTests: XCTestCase {

    /// A model backed by throwaway defaults, so tests never read or write the
    /// real app's saved settings.
    private func makeModel(
        _ name: String = UUID().uuidString
    ) throws -> HandEntryModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HandEntryModelTests.\(name)"))
        defaults.removePersistentDomain(forName: "HandEntryModelTests.\(name)")
        return HandEntryModel(defaults: defaults)
    }

    private func tile(_ notation: String) throws -> Tile {
        try Tile(notation)
    }

    // MARK: Defaults on a fresh hand

    func test_selfDrawn_isOffByDefault() throws {
        let model = try makeModel()
        XCTAssertFalse(model.selfDrawn, "most wins are off a discard, not self-drawn")
    }

    func test_declaredReady_isOnByDefault() throws {
        let model = try makeModel()
        XCTAssertTrue(model.declaredTing, "this table declares ready on nearly every win")
    }

    func test_situationalBonuses_areOffByDefault() throws {
        let model = try makeModel()
        XCTAssertFalse(model.lastTile)
        XCTAssertFalse(model.afterKong)
        XCTAssertFalse(model.afterKongOnKong)
        XCTAssertFalse(model.afterFlower)
        XCTAssertFalse(model.robbingKong)
        XCTAssertFalse(model.heavenlyHand)
        XCTAssertFalse(model.earthlyHand)
        XCTAssertFalse(model.humanHand)
        XCTAssertEqual(model.turnsBeforeWin, "")
    }

    // MARK: Clear

    func test_clearHand_resetsSelfDrawnToOff() throws {
        let model = try makeModel()
        model.selfDrawn = true
        model.clearHand()
        XCTAssertFalse(model.selfDrawn, "Clear starts a fresh hand, so self-drawn goes back off")
    }

    func test_clearHand_restoresDeclaredReadyToOn() throws {
        let model = try makeModel()
        model.declaredTing = false
        model.clearHand()
        XCTAssertTrue(model.declaredTing)
    }

    func test_clearHand_clearsTilesAndSituations() throws {
        let model = try makeModel()
        model.add(try tile("1m"))
        model.add(try tile("1f"))
        model.lastTile = true
        model.humanHand = true
        model.turnsBeforeWin = "5"

        model.clearHand()

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.bodyCount, 0)
        XCTAssertTrue(model.flowers.isEmpty)
        XCTAssertNil(model.winningId)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.lastTile)
        XCTAssertFalse(model.humanHand)
        XCTAssertEqual(model.turnsBeforeWin, "")
    }

    /// Base/round/seat/dealer are table settings, not per-hand state — Clear
    /// starts the next hand at the same table, so they must survive it.
    func test_clearHand_keepsTableSettings() throws {
        let model = try makeModel()
        model.taiBase = 9
        model.roundWind = .south
        model.seatWind = .west
        model.isDealer = true

        model.clearHand()

        XCTAssertEqual(model.taiBase, 9)
        XCTAssertEqual(model.roundWind, .south)
        XCTAssertEqual(model.seatWind, .west)
        XCTAssertTrue(model.isDealer)
    }

    // MARK: Self-drawn reaches the score

    func test_selfDrawn_off_doesNotAwardSelfDraw() throws {
        let model = try makeModel()
        enterSampleHand(model)
        model.selfDrawn = false
        model.score()
        let ids = try XCTUnwrap(model.breakdown).awards.map(\.ruleId)
        XCTAssertFalse(ids.contains("self-draw"))
    }

    func test_selfDrawn_on_awardsSelfDraw() throws {
        let model = try makeModel()
        enterSampleHand(model)
        model.selfDrawn = true
        model.score()
        let ids = try XCTUnwrap(model.breakdown).awards.map(\.ruleId)
        XCTAssertTrue(ids.contains("self-draw"))
    }

    /// 123m + 111p + 123s + EEE concealed, 555p exposed, NN eye, one flower.
    private func enterSampleHand(_ model: HandEntryModel) {
        model.target = .exposed
        for n in ["5p", "5p", "5p"] { model.add(try! Tile(n)) }
        model.target = .concealed
        for n in ["1m", "2m", "3m", "1p", "1p", "1p", "1s", "2s", "3s",
                  "Ew", "Ew", "Ew", "Nw", "Nw"] {
            model.add(try! Tile(n))
        }
        model.add(try! Tile("1f"))
    }
}
