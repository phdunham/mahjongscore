import XCTest
@testable import MahjongCore

final class TileParsingTests: XCTestCase {

    // MARK: - Round-trip

    func test_allNumericTiles_roundTrip() throws {
        for suit in Suit.allCases {
            for rank in 1...9 {
                let tile = Tile.numeric(suit, rank)
                let parsed = try Tile(tile.notation)
                XCTAssertEqual(parsed, tile, "round-trip failed for \(tile.notation)")
            }
        }
    }

    func test_allWinds_roundTrip() throws {
        for w in Wind.allCases {
            let tile = Tile.wind(w)
            XCTAssertEqual(try Tile(tile.notation), tile)
        }
    }

    func test_allDragons_roundTrip() throws {
        for d in Dragon.allCases {
            let tile = Tile.dragon(d)
            XCTAssertEqual(try Tile(tile.notation), tile)
        }
    }

    func test_allFlowers_roundTrip() throws {
        for kind in FlowerKind.allCases {
            for i in 1...4 {
                let tile = Tile.flower(Flower(kind: kind, index: i)!)
                XCTAssertEqual(try Tile(tile.notation), tile, "flower round-trip failed for \(tile.notation)")
            }
        }
    }

    // MARK: - Canonical notation spot checks

    func test_notationSpotChecks() {
        XCTAssertEqual(Tile.numeric(.man, 1).notation, "1m")
        XCTAssertEqual(Tile.numeric(.pin, 9).notation, "9p")
        XCTAssertEqual(Tile.numeric(.sou, 5).notation, "5s")
        XCTAssertEqual(Tile.wind(.east).notation, "Ew")
        XCTAssertEqual(Tile.wind(.north).notation, "Nw")
        XCTAssertEqual(Tile.dragon(.red).notation, "Rd")
        XCTAssertEqual(Tile.dragon(.green).notation, "Gd")
        XCTAssertEqual(Tile.dragon(.white).notation, "Wd")
        XCTAssertEqual(Tile.flower(Flower(kind: .season, index: 1)!).notation, "1f")
        XCTAssertEqual(Tile.flower(Flower(kind: .season, index: 4)!).notation, "4f")
        XCTAssertEqual(Tile.flower(Flower(kind: .plant, index: 1)!).notation, "5f")
        XCTAssertEqual(Tile.flower(Flower(kind: .plant, index: 4)!).notation, "8f")
    }

    // MARK: - Parsing errors

    func test_empty_throwsEmpty() {
        XCTAssertThrowsError(try Tile("")) { error in
            XCTAssertEqual(error as? Tile.ParseError, .empty)
        }
        XCTAssertThrowsError(try Tile("   ")) { error in
            XCTAssertEqual(error as? Tile.ParseError, .empty)
        }
    }

    func test_unknownFormat_throws() {
        for bad in ["x", "xxx", "0x", "10m", "ab", "Rx", "Ex", "9f"] where bad != "9f" {
            XCTAssertThrowsError(try Tile(bad), "expected throw for '\(bad)'")
        }
    }

    func test_invalidRank_throws() {
        XCTAssertThrowsError(try Tile("0m")) { error in
            XCTAssertEqual(error as? Tile.ParseError, .invalidRank(0))
        }
    }

    func test_invalidFlowerIndex_throws() {
        XCTAssertThrowsError(try Tile("9f")) { error in
            XCTAssertEqual(error as? Tile.ParseError, .invalidFlowerIndex(9))
        }
        XCTAssertThrowsError(try Tile("0f")) { error in
            XCTAssertEqual(error as? Tile.ParseError, .invalidFlowerIndex(0))
        }
    }

    func test_whitespaceTrimmed() throws {
        XCTAssertEqual(try Tile("  3m  "), .numeric(.man, 3))
    }

    // MARK: - Display names

    func test_displayNames() {
        XCTAssertEqual(Tile.numeric(.man, 1).displayName, "1萬")
        XCTAssertEqual(Tile.numeric(.pin, 9).displayName, "9筒")
        XCTAssertEqual(Tile.numeric(.sou, 5).displayName, "5條")
        XCTAssertEqual(Tile.wind(.east).displayName, "東")
        XCTAssertEqual(Tile.dragon(.red).displayName, "中")
        XCTAssertEqual(Tile.dragon(.green).displayName, "發")
        XCTAssertEqual(Tile.dragon(.white).displayName, "白")
        XCTAssertEqual(Tile.flower(Flower(kind: .season, index: 1)!).displayName, "春")
        XCTAssertEqual(Tile.flower(Flower(kind: .plant, index: 4)!).displayName, "竹")
    }

    // MARK: - Predicates

    func test_isHonor() {
        XCTAssertTrue(Tile.wind(.east).isHonor)
        XCTAssertTrue(Tile.dragon(.red).isHonor)
        XCTAssertFalse(Tile.numeric(.man, 1).isHonor)
        XCTAssertFalse(Tile.flower(Flower(kind: .season, index: 1)!).isHonor)
    }

    func test_isFlowerAndNumeric() {
        XCTAssertTrue(Tile.flower(Flower(kind: .plant, index: 2)!).isFlower)
        XCTAssertFalse(Tile.numeric(.sou, 3).isFlower)
        XCTAssertTrue(Tile.numeric(.sou, 3).isNumeric)
        XCTAssertFalse(Tile.wind(.south).isNumeric)
    }

    func test_isTerminalAndSimple() {
        XCTAssertTrue(Tile.numeric(.man, 1).isTerminal)
        XCTAssertTrue(Tile.numeric(.sou, 9).isTerminal)
        XCTAssertFalse(Tile.numeric(.pin, 5).isTerminal)
        XCTAssertTrue(Tile.numeric(.pin, 5).isSimple)
        XCTAssertFalse(Tile.numeric(.pin, 1).isSimple)
        XCTAssertFalse(Tile.wind(.east).isTerminal)
        XCTAssertFalse(Tile.wind(.east).isSimple)
    }

    // MARK: - Flower seat matching

    func test_flowerSeatWind() {
        XCTAssertEqual(Flower(kind: .season, index: 1)!.seatWind, .east)
        XCTAssertEqual(Flower(kind: .season, index: 2)!.seatWind, .south)
        XCTAssertEqual(Flower(kind: .plant, index: 3)!.seatWind, .west)
        XCTAssertEqual(Flower(kind: .plant, index: 4)!.seatWind, .north)
    }

    func test_flowerInit_rejectsOutOfRange() {
        XCTAssertNil(Flower(kind: .season, index: 0))
        XCTAssertNil(Flower(kind: .season, index: 5))
        XCTAssertNil(Flower(kind: .plant, index: -1))
    }

    // MARK: - Canonical ordering

    func test_sortOrder() {
        let unsorted: [Tile] = [
            .dragon(.white),
            .numeric(.sou, 1),
            .flower(Flower(kind: .plant, index: 1)!),
            .numeric(.man, 9),
            .wind(.south),
            .numeric(.pin, 5),
            .numeric(.man, 1),
            .dragon(.red),
            .flower(Flower(kind: .season, index: 4)!),
            .wind(.east),
        ]
        let expected: [Tile] = [
            .numeric(.man, 1),
            .numeric(.man, 9),
            .numeric(.pin, 5),
            .numeric(.sou, 1),
            .wind(.east),
            .wind(.south),
            .dragon(.red),
            .dragon(.white),
            .flower(Flower(kind: .season, index: 4)!),
            .flower(Flower(kind: .plant, index: 1)!),
        ]
        XCTAssertEqual(unsorted.sorted(), expected)
    }

    // MARK: - Codable

    func test_codable_roundTrip_singleTile() throws {
        let tile = Tile.numeric(.pin, 7)
        let data = try JSONEncoder().encode(tile)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"7p\"")
        let decoded = try JSONDecoder().decode(Tile.self, from: data)
        XCTAssertEqual(decoded, tile)
    }

    func test_codable_roundTrip_array() throws {
        let tiles: [Tile] = [
            .numeric(.man, 1), .wind(.east), .dragon(.green),
            .flower(Flower(kind: .plant, index: 2)!),
        ]
        let data = try JSONEncoder().encode(tiles)
        let decoded = try JSONDecoder().decode([Tile].self, from: data)
        XCTAssertEqual(decoded, tiles)
    }

    // MARK: - Catalog counts

    func test_allNonFlowerKinds_has34Entries() {
        XCTAssertEqual(Tile.allNonFlowerKinds.count, 34)
    }

    func test_allFlowers_has8Entries() {
        XCTAssertEqual(Tile.allFlowers.count, 8)
    }
}
