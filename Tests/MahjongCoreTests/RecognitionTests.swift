import XCTest
@testable import MahjongCore

final class RecognitionTests: XCTestCase {

    // MARK: - requestBody smoke

    func test_requestBody_hasExpectedShape() {
        let body = ClaudeRecognizer.requestBody(
            model: .sonnet46, mediaType: "image/jpeg", base64Image: "FAKE"
        )
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-4-6")
        let toolChoice = body["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "submit_hand")

        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)
        XCTAssertEqual(content?.first?["type"] as? String, "image")
        let source = content?.first?["source"] as? [String: Any]
        XCTAssertEqual(source?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source?["data"] as? String, "FAKE")
    }

    // MARK: - extractToolUse / toRecognizedTiles happy paths

    func test_twoRow_withWinningTile() throws {
        let body: [String: Any] = [
            "id": "msg_test",
            "content": [
                [
                    "type": "tool_use",
                    "id": "toolu_xxx",
                    "name": "submit_hand",
                    "input": [
                        "rows": [
                            [
                                "placement": "upper",
                                "tiles": ["1m", "2m", "3m", "4m", "5m", "6m", "Ew"],
                            ],
                            [
                                "placement": "lower",
                                "tiles": ["5p", "5p", "5p", "9s", "9s", "9s"],
                            ],
                        ],
                        "flowers": ["1f", "6f"],
                        "winning_tile": "Ew",
                    ],
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertEqual(dto.rows.count, 2)
        XCTAssertEqual(dto.rows[0].placement, "upper")
        XCTAssertEqual(dto.rows[1].placement, "lower")
        XCTAssertEqual(dto.flowers, ["1f", "6f"])
        XCTAssertEqual(dto.winning_tile, "Ew")

        let recognized = try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)
        XCTAssertEqual(recognized.rows.count, 2)
        XCTAssertEqual(recognized.rows[0].placement, .upper)
        XCTAssertEqual(recognized.rows[1].placement, .lower)
        XCTAssertEqual(recognized.rows[0].tiles.count, 7)
        XCTAssertEqual(recognized.rows[1].tiles.count, 6)
        XCTAssertEqual(recognized.flowers.count, 2)
        XCTAssertEqual(recognized.winningTile, try Tile("Ew"))
        XCTAssertEqual(recognized.defaultConcealedTiles.count, 7)
        XCTAssertEqual(recognized.reportedExposedTiles.count, 6)
        XCTAssertFalse(recognized.isSingleRow)
    }

    func test_singleRow_noWinningTile() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_hand",
                    "input": [
                        "rows": [
                            [
                                "placement": "single",
                                "tiles": ["1m", "2m", "3m", "4m", "5m", "6m"],
                            ],
                        ],
                        "flowers": [],
                        "winning_tile": "",
                    ],
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        let recognized = try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)
        XCTAssertTrue(recognized.isSingleRow)
        XCTAssertNil(recognized.winningTile)
        XCTAssertEqual(recognized.defaultConcealedTiles.count, 6)
        XCTAssertTrue(recognized.reportedExposedTiles.isEmpty)
    }

    func test_winningTileOmitted() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_hand",
                    "input": [
                        "rows": [
                            ["placement": "single", "tiles": ["1m"]],
                        ],
                        "flowers": [],
                        // no winning_tile key at all
                    ],
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertNil(dto.winning_tile)
        let recognized = try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)
        XCTAssertNil(recognized.winningTile)
    }

    // MARK: - extractToolUse error paths

    func test_noToolUseBlock_throws() throws {
        let body: [String: Any] = [
            "content": [["type": "text", "text": "Sorry, can't see the image."]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertThrowsError(try ClaudeRecognizer.extractToolUse(from: data)) { error in
            XCTAssertEqual(error as? ClaudeRecognizer.RecognitionError, .noToolUseBlock)
        }
    }

    func test_skipsTextBlockBeforeToolUse() throws {
        let body: [String: Any] = [
            "content": [
                ["type": "text", "text": "Here are the tiles."],
                [
                    "type": "tool_use", "name": "submit_hand",
                    "input": [
                        "rows": [["placement": "single", "tiles": ["5p", "5p"]]],
                        "flowers": [],
                    ]
                ],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertEqual(dto.rows[0].tiles, ["5p", "5p"])
    }

    func test_malformedJson_throws() {
        XCTAssertThrowsError(try ClaudeRecognizer.extractToolUse(from: Data("x".utf8)))
    }

    func test_invalidPlacement_throws() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use", "name": "submit_hand",
                    "input": [
                        "rows": [["placement": "sideways", "tiles": ["1m"]]],
                        "flowers": [],
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertThrowsError(try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil))
    }

    // MARK: - parseTiles

    func test_parseTiles_happyPath() throws {
        let tiles = try ClaudeRecognizer.parseTiles(["1m", "9p", "Ew", "Rd", "5f"])
        XCTAssertEqual(tiles.count, 5)
        XCTAssertEqual(tiles[0], try Tile("1m"))
        XCTAssertEqual(tiles[4], try Tile("5f"))
    }

    func test_parseTiles_invalidNotation_throwsWithDetail() {
        XCTAssertThrowsError(try ClaudeRecognizer.parseTiles(["1m", "bogus", "3m"])) { error in
            XCTAssertEqual(error as? ClaudeRecognizer.RecognitionError,
                           .tileParseFailure(notation: "bogus"))
        }
    }

    // MARK: - Protocol conformance via mock

    struct MockRecognizer: ImageRecognizer {
        let result: RecognizedTiles
        func recognize(imageData _: Data) async throws -> RecognizedTiles { result }
    }

    func test_mockRecognizer_protocolConformance() async throws {
        let spring = Tile.flower(Flower(kind: .season, index: 1)!)
        let canned = RecognizedTiles(
            rows: [.init(placement: .upper, tiles: [try Tile("1m"), try Tile("Ew")])],
            flowers: [spring],
            winningTile: try Tile("Ew")
        )
        let mock = MockRecognizer(result: canned)
        let got = try await mock.recognize(imageData: Data())
        XCTAssertEqual(got.rows.first?.tiles.count, 2)
        XCTAssertEqual(got.flowers, [spring])
        XCTAssertEqual(got.winningTile, try Tile("Ew"))
    }
}
