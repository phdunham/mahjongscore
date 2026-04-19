import XCTest
@testable import MahjongCore

final class MeldTests: XCTestCase {

    // MARK: - Helpers

    private func t(_ s: String) -> Tile {
        // convenience; tests below only pass known-good notations
        try! Tile(s)
    }

    // MARK: - Chow

    func test_validChows_inAllSuits() throws {
        _ = try Meld(kind: .chow, tiles: [t("1m"), t("2m"), t("3m")], isConcealed: true)
        _ = try Meld(kind: .chow, tiles: [t("4p"), t("5p"), t("6p")], isConcealed: false)
        _ = try Meld(kind: .chow, tiles: [t("7s"), t("8s"), t("9s")], isConcealed: true)
    }

    func test_chow_acceptsOutOfOrderInput_thenSorts() throws {
        let m = try Meld(kind: .chow, tiles: [t("3m"), t("1m"), t("2m")], isConcealed: true)
        XCTAssertEqual(m.tiles, [t("1m"), t("2m"), t("3m")])
    }

    func test_chow_acrossSuits_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .chow, tiles: [t("1m"), t("2p"), t("3s")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .chowAcrossSuits) }
    }

    func test_chow_notConsecutive_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .chow, tiles: [t("1m"), t("2m"), t("4m")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .chowNotConsecutive) }
    }

    func test_chow_containingHonor_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .chow, tiles: [t("1m"), t("2m"), t("Ew")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .chowContainsNonNumeric) }
    }

    // MARK: - Pung

    func test_validPungs_numericAndHonors() throws {
        _ = try Meld(kind: .pung, tiles: [t("5p"), t("5p"), t("5p")], isConcealed: true)
        _ = try Meld(kind: .pung, tiles: [t("Ew"), t("Ew"), t("Ew")], isConcealed: false)
        _ = try Meld(kind: .pung, tiles: [t("Rd"), t("Rd"), t("Rd")], isConcealed: true)
    }

    func test_pung_notIdentical_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .pung, tiles: [t("5p"), t("5p"), t("6p")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .pungNotIdentical) }
    }

    // MARK: - Kong

    func test_validKong() throws {
        let m = try Meld(kind: .kong, tiles: [t("9s"), t("9s"), t("9s"), t("9s")], isConcealed: true)
        XCTAssertTrue(m.isKong)
        XCTAssertEqual(m.tiles.count, 4)
    }

    func test_kong_notIdentical_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .kong, tiles: [t("9s"), t("9s"), t("9s"), t("8s")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .kongNotIdentical) }
    }

    func test_kong_wrongCount_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .kong, tiles: [t("9s"), t("9s"), t("9s")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .wrongTileCount(kind: .kong, got: 3)) }
    }

    // MARK: - Pair

    func test_validPair() throws {
        _ = try Meld(kind: .pair, tiles: [t("Nw"), t("Nw")], isConcealed: true)
    }

    func test_pair_notIdentical_throws() {
        XCTAssertThrowsError(
            try Meld(kind: .pair, tiles: [t("Nw"), t("Ew")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .pairNotIdentical) }
    }

    // MARK: - Flowers rejected

    func test_flowerInMeld_throws() {
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)
        XCTAssertThrowsError(
            try Meld(kind: .pung, tiles: [spring, spring, spring], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .flowerNotAllowed) }
    }

    // MARK: - Wrong count per kind

    func test_wrongCount_pair() {
        XCTAssertThrowsError(
            try Meld(kind: .pair, tiles: [t("1m")], isConcealed: true)
        ) { XCTAssertEqual($0 as? Meld.ValidationError, .wrongTileCount(kind: .pair, got: 1)) }
    }

    // MARK: - Derived properties

    func test_derivedProperties() throws {
        let terminalPung = try Meld(kind: .pung, tiles: [t("1m"), t("1m"), t("1m")], isConcealed: true)
        XCTAssertTrue(terminalPung.isAllTerminal)
        XCTAssertFalse(terminalPung.isAllHonor)
        XCTAssertEqual(terminalPung.numericSuit, .man)

        let honorPung = try Meld(kind: .pung, tiles: [t("Rd"), t("Rd"), t("Rd")], isConcealed: true)
        XCTAssertFalse(honorPung.isAllTerminal)
        XCTAssertTrue(honorPung.isAllHonor)
        XCTAssertNil(honorPung.numericSuit)

        let chow = try Meld(kind: .chow, tiles: [t("1m"), t("2m"), t("3m")], isConcealed: true)
        XCTAssertFalse(chow.isAllTerminal)
        XCTAssertFalse(chow.isAllHonor)
        XCTAssertEqual(chow.numericSuit, .man)
        XCTAssertEqual(chow.baseTile, t("1m"))

        let eye = try Meld(kind: .pair, tiles: [t("5p"), t("5p")], isConcealed: true)
        XCTAssertTrue(eye.isEye)
        XCTAssertFalse(eye.isKong)
    }

    // MARK: - Codable

    func test_meld_codable_roundTrip() throws {
        let original = try Meld(kind: .chow, tiles: [t("3s"), t("4s"), t("5s")], isConcealed: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Meld.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
