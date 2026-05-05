import XCTest
@testable import MahjongCore

final class RecognitionTests: XCTestCase {

    // MARK: - requestBody smoke

    func test_requestBody_hasExpectedShape() {
        let body = ClaudeRecognizer.requestBody(
            model: .sonnet46, mediaType: "image/jpeg", base64Image: "FAKE"
        )
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-4-6")

        // The instruction prompt now lives in the system block with
        // ephemeral cache_control so subsequent calls hit Anthropic's prompt
        // cache. Verify both the cache marker and that the prompt text is present.
        let system = body["system"] as? [[String: Any]]
        XCTAssertEqual(system?.count, 1)
        XCTAssertEqual(system?.first?["type"] as? String, "text")
        let cacheControl = system?.first?["cache_control"] as? [String: Any]
        XCTAssertEqual(cacheControl?["type"] as? String, "ephemeral")
        XCTAssertNotNil(system?.first?["text"] as? String)

        let toolChoice = body["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "submit_hand")

        // The user message should now contain just the image (text moved to system).
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?.first?["type"] as? String, "image")
        let source = content?.first?["source"] as? [String: Any]
        XCTAssertEqual(source?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source?["data"] as? String, "FAKE")
    }

    func test_singleTileRequestBody_hasCacheControl() {
        let body = ClaudeRecognizer.singleTileRequestBody(
            model: .sonnet46, mediaType: "image/jpeg", base64Image: "FAKE"
        )
        let system = body["system"] as? [[String: Any]]
        XCTAssertEqual(system?.first?["cache_control"] as? [String: String],
                       ["type": "ephemeral"])
        let toolChoice = body["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["name"] as? String, "submit_tile")
    }

    // MARK: - extractToolUse / toRecognizedTiles happy paths

    func test_twoRow_withBBoxesConfidenceAndWinningTile() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_hand",
                    "input": [
                        "rows": [
                            [
                                "placement": "upper",
                                "tiles": [
                                    ["notation": "1m", "bbox": ["x": 0.05, "y": 0.10, "width": 0.07, "height": 0.20], "confidence": 0.97],
                                    ["notation": "2m", "bbox": ["x": 0.12, "y": 0.10, "width": 0.07, "height": 0.20], "confidence": 0.95],
                                    ["notation": "3m", "confidence": 0.4],
                                ],
                            ],
                            [
                                "placement": "lower",
                                "tiles": [
                                    ["notation": "5p", "bbox": ["x": 0.05, "y": 0.50, "width": 0.07, "height": 0.20], "confidence": 0.62],
                                    ["notation": "5p", "bbox": ["x": 0.12, "y": 0.50, "width": 0.07, "height": 0.20]],
                                ],
                            ],
                        ],
                        "flowers": [
                            ["notation": "1f", "bbox": ["x": 0.85, "y": 0.05, "width": 0.10, "height": 0.15], "confidence": 0.9],
                        ],
                        "winning_tile": [
                            "notation": "3m",
                            "bbox": ["x": 0.19, "y": 0.07, "width": 0.07, "height": 0.20],
                            "confidence": 0.5,
                        ],
                    ],
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertEqual(dto.rows.count, 2)
        XCTAssertEqual(dto.rows[0].tiles[0].notation, "1m")
        XCTAssertEqual(dto.rows[0].tiles[0].bbox?.x, 0.05)
        XCTAssertEqual(dto.rows[0].tiles[0].confidence, 0.97)
        XCTAssertEqual(dto.rows[0].tiles[2].confidence, 0.4)
        XCTAssertNil(dto.rows[0].tiles[2].bbox)  // 3m had no bbox
        XCTAssertNil(dto.rows[1].tiles[1].confidence)  // missing field tolerated
        XCTAssertEqual(dto.winning_tile?.notation, "3m")
        XCTAssertEqual(dto.winning_tile?.confidence, 0.5)

        let recognized = try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)
        XCTAssertEqual(recognized.rows.count, 2)
        XCTAssertEqual(recognized.rows[0].tiles[0].confidence, 0.97)
        XCTAssertEqual(recognized.rows[0].tiles[2].confidence, 0.4)
        XCTAssertNil(recognized.rows[1].tiles[1].confidence)
        XCTAssertEqual(recognized.flowers.first?.confidence, 0.9)
        XCTAssertEqual(recognized.winningTile?.confidence, 0.5)
        XCTAssertEqual(recognized.bodyTiles.count, 5)
        XCTAssertEqual(recognized.defaultConcealedTiles.count, 3)
        XCTAssertEqual(recognized.reportedExposedTiles.count, 2)
    }

    func test_singleRow_noBBox_noWinningTile() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_hand",
                    "input": [
                        "rows": [
                            [
                                "placement": "single",
                                "tiles": [
                                    ["notation": "1m"],
                                    ["notation": "2m"],
                                    ["notation": "3m"],
                                ],
                            ],
                        ],
                        "flowers": [],
                    ],
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        let recognized = try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)
        XCTAssertTrue(recognized.isSingleRow)
        XCTAssertNil(recognized.winningTile)
        XCTAssertTrue(recognized.rows[0].tiles.allSatisfy { $0.bbox == nil })
    }

    // MARK: - Errors

    func test_noToolUseBlock_throws() throws {
        let body: [String: Any] = [
            "content": [["type": "text", "text": "Can't see the image."]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertThrowsError(try ClaudeRecognizer.extractToolUse(from: data)) { error in
            XCTAssertEqual(error as? ClaudeRecognizer.RecognitionError, .noToolUseBlock)
        }
    }

    func test_invalidPlacement_throws() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use", "name": "submit_hand",
                    "input": [
                        "rows": [["placement": "sideways", "tiles": [["notation": "1m"]]]],
                        "flowers": [],
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertThrowsError(try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil))
    }

    func test_invalidNotation_throws() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use", "name": "submit_hand",
                    "input": [
                        "rows": [["placement": "single", "tiles": [["notation": "XX"]]]],
                        "flowers": [],
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractToolUse(from: data)
        XCTAssertThrowsError(try ClaudeRecognizer.toRecognizedTiles(dto, rawResponse: nil)) { error in
            XCTAssertEqual(error as? ClaudeRecognizer.RecognitionError,
                           .tileParseFailure(notation: "XX"))
        }
    }

    // MARK: - BBox validity

    func test_bbox_isValid() {
        XCTAssertTrue(BBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2).isValid)
        XCTAssertTrue(BBox(x: 0, y: 0, width: 1, height: 1).isValid)
        XCTAssertFalse(BBox(x: -0.1, y: 0, width: 0.2, height: 0.2).isValid)
        XCTAssertFalse(BBox(x: 0, y: 0, width: 0, height: 0.2).isValid)
        XCTAssertFalse(BBox(x: 0.9, y: 0, width: 0.3, height: 0.2).isValid)  // overflows right
    }

    // MARK: - Single-tile re-verification parsing

    func test_singleTile_extract_happyPath() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_tile",
                    "input": ["notation": "5p", "confidence": 0.88],
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractSingleTileToolUse(from: data)
        XCTAssertEqual(dto.notation, "5p")
        XCTAssertEqual(dto.confidence, 0.88)
    }

    func test_singleTile_extract_confidenceOptional() throws {
        let body: [String: Any] = [
            "content": [
                [
                    "type": "tool_use",
                    "name": "submit_tile",
                    "input": ["notation": "Ew"],  // no confidence reported
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let dto = try ClaudeRecognizer.extractSingleTileToolUse(from: data)
        XCTAssertEqual(dto.notation, "Ew")
        XCTAssertNil(dto.confidence)
    }

    func test_singleTile_extract_missingToolUse_throws() throws {
        let body: [String: Any] = [
            "content": [["type": "text", "text": "hmm"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertThrowsError(try ClaudeRecognizer.extractSingleTileToolUse(from: data)) { error in
            XCTAssertEqual(error as? ClaudeRecognizer.RecognitionError, .noToolUseBlock)
        }
    }

    // MARK: - Mock recognizer

    struct MockRecognizer: ImageRecognizer {
        let result: RecognizedTiles
        func recognize(imageData _: Data) async throws -> RecognizedTiles { result }
    }

    func test_mockRecognizer_protocolConformance() async throws {
        let canned = RecognizedTiles(
            rows: [
                .init(placement: .upper, tiles: [
                    RecognizedTile(tile: try Tile("1m"), bbox: BBox(x: 0.1, y: 0.1, width: 0.1, height: 0.2)),
                    RecognizedTile(tile: try Tile("Ew")),
                ]),
            ],
            flowers: [],
            winningTile: RecognizedTile(tile: try Tile("Ew"))
        )
        let mock = MockRecognizer(result: canned)
        let got = try await mock.recognize(imageData: Data())
        XCTAssertEqual(got.rows.first?.tiles.count, 2)
        XCTAssertEqual(got.winningTile?.tile, try Tile("Ew"))
    }
}
