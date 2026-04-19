import Foundation

/// Vision-based tile recognizer that calls Anthropic's Messages API.
///
/// Claude is forced via `tool_use` to return its answer as a structured payload
/// describing the row layout, flowers, and the half-raised winning tile. This
/// avoids free-form-text parsing and lets the recognizer communicate concealed vs.
/// exposed (upper row vs. lower row by user convention).
public struct ClaudeRecognizer: ImageRecognizer {

    // MARK: - Configuration

    public enum Model: String, Sendable {
        case opus47 = "claude-opus-4-7"
        case sonnet46 = "claude-sonnet-4-6"
        case haiku45 = "claude-haiku-4-5-20251001"
    }

    public enum RecognitionError: Error, Equatable {
        case apiError(status: Int, body: String)
        case unexpectedResponseShape(String)
        case noToolUseBlock
        case tileParseFailure(notation: String)
    }

    public let apiKey: String
    public let model: Model
    public let mediaType: String   // "image/jpeg" or "image/png"
    public let session: URLSession

    /// Allows tests / app layer to override the endpoint. Defaults to the public API.
    public let endpoint: URL

    public init(
        apiKey: String,
        model: Model = .sonnet46,
        mediaType: String = "image/jpeg",
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.mediaType = mediaType
        self.session = session
        self.endpoint = endpoint
    }

    // MARK: - Entry point

    public func recognize(imageData: Data) async throws -> RecognizedTiles {
        let body = Self.requestBody(
            model: model,
            mediaType: mediaType,
            base64Image: imageData.base64EncodedString()
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecognitionError.unexpectedResponseShape("not an HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "(non-utf8 body)"
            throw RecognitionError.apiError(status: http.statusCode, body: msg)
        }

        let dto = try Self.extractToolUse(from: data)
        let recognized = try Self.toRecognizedTiles(
            dto,
            rawResponse: String(data: data, encoding: .utf8)
        )
        return recognized
    }

    // MARK: - Static helpers (easy to unit-test offline)

    static func requestBody(model: Model, mediaType: String, base64Image: String) -> [String: Any] {
        [
            "model": model.rawValue,
            "max_tokens": 2048,
            "tools": [
                [
                    "name": "submit_hand",
                    "description": "Record the layout of tiles identified in the photo.",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "rows": [
                                "type": "array",
                                "description": "Body-tile rows in top-to-bottom order. Use `upper` for the upper row when there are two rows, `lower` for the lower row, or `single` when only one row is present.",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "placement": [
                                            "type": "string",
                                            "enum": ["upper", "lower", "single"],
                                        ],
                                        "tiles": [
                                            "type": "array",
                                            "items": ["type": "string"],
                                            "description": "Tile notations in reading order (left to right), including the winning tile even if it's half-raised.",
                                        ],
                                    ],
                                    "required": ["placement", "tiles"],
                                ],
                            ],
                            "flowers": [
                                "type": "array",
                                "items": ["type": "string"],
                                "description": "Flower tiles visible in the photo (usually arranged separately from the body rows).",
                            ],
                            "winning_tile": [
                                "type": "string",
                                "description": "Notation of the half-raised tile that completed the hand. Omit or leave empty if no tile is half-raised.",
                            ],
                        ],
                        "required": ["rows", "flowers"],
                    ],
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_hand"],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mediaType,
                                "data": base64Image,
                            ],
                        ],
                        [
                            "type": "text",
                            "text": recognitionPrompt,
                        ],
                    ],
                ]
            ],
        ]
    }

    /// Intermediate DTO mirroring the `submit_hand` tool schema.
    struct HandDTO: Decodable {
        struct RowDTO: Decodable {
            let placement: String
            let tiles: [String]
        }
        let rows: [RowDTO]
        let flowers: [String]
        let winning_tile: String?
    }

    /// Walk a Messages-API response, find the `submit_hand` tool_use block,
    /// and decode its input into a `HandDTO`.
    static func extractToolUse(from data: Data) throws -> HandDTO {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecognitionError.unexpectedResponseShape("top-level not a JSON object")
        }
        guard let content = top["content"] as? [[String: Any]] else {
            throw RecognitionError.unexpectedResponseShape("missing content array")
        }
        for block in content {
            guard (block["type"] as? String) == "tool_use" else { continue }
            guard let input = block["input"] else {
                throw RecognitionError.unexpectedResponseShape("tool_use missing input")
            }
            let inputData = try JSONSerialization.data(withJSONObject: input)
            do {
                return try JSONDecoder().decode(HandDTO.self, from: inputData)
            } catch {
                throw RecognitionError.unexpectedResponseShape("tool_use input decode failed: \(error)")
            }
        }
        throw RecognitionError.noToolUseBlock
    }

    /// Convert a parsed `HandDTO` into the public `RecognizedTiles` type, parsing
    /// each tile notation and mapping placement strings.
    static func toRecognizedTiles(_ dto: HandDTO, rawResponse: String?) throws -> RecognizedTiles {
        var rows: [RecognizedTiles.Row] = []
        for rowDTO in dto.rows {
            guard let placement = RecognizedTiles.Placement(rawValue: rowDTO.placement) else {
                throw RecognitionError.unexpectedResponseShape(
                    "unknown placement '\(rowDTO.placement)'"
                )
            }
            let tiles = try parseTiles(rowDTO.tiles)
            rows.append(RecognizedTiles.Row(placement: placement, tiles: tiles))
        }
        let flowers = try parseTiles(dto.flowers)

        let winning: Tile?
        if let notation = dto.winning_tile?.trimmingCharacters(in: .whitespaces),
           !notation.isEmpty {
            winning = try? Tile(notation)
        } else {
            winning = nil
        }
        return RecognizedTiles(
            rows: rows, flowers: flowers,
            winningTile: winning, rawResponse: rawResponse
        )
    }

    static func parseTiles(_ notations: [String]) throws -> [Tile] {
        var out: [Tile] = []
        for n in notations {
            do {
                out.append(try Tile(n))
            } catch {
                throw RecognitionError.tileParseFailure(notation: n)
            }
        }
        return out
    }

    // MARK: - Convenience

    /// Read the API key from the `ANTHROPIC_API_KEY` environment variable.
    /// Returns `nil` if unset or empty.
    public static func fromEnvironment(
        model: Model = .sonnet46,
        mediaType: String = "image/jpeg"
    ) -> ClaudeRecognizer? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty
        else { return nil }
        return ClaudeRecognizer(apiKey: key, model: model, mediaType: mediaType)
    }

    // MARK: - Prompt

    public static let recognitionPrompt: String = """
    You are identifying tiles in a photo of a Taiwan 16-tile mahjong winning hand.

    LAYOUT CONVENTIONS
    - The photo has ONE or TWO rows of body tiles (flowers are separate).
    - TWO rows: the UPPER row is the concealed hand, the LOWER row is exposed
      (called) melds. Report these with placement="upper" and "lower".
    - ONE row: report placement="single" — concealment is decided later.
    - One body tile may be visibly HALF-RAISED above its neighbors. That's the
      WINNING TILE. Include it in its row's tile list AND report its notation as
      winning_tile. Omit winning_tile only if no tile is half-raised.
    - FLOWERS are usually off to the side or on top. They have 春夏秋冬 or
      梅蘭菊竹 artwork, distinct from the numbered / wind / dragon tiles.

    TILE NOTATION
    - 1m-9m  : characters (萬)
    - 1p-9p  : dots / circles (筒)
    - 1s-9s  : bamboo (條)
    - Ew, Sw, Ww, Nw : winds (東, 南, 西, 北)
    - Rd, Gd, Wd     : dragons (中, 發, 白)
    - 1f-4f  : season flowers, numbered 春=1 夏=2 秋=3 冬=4
    - 5f-8f  : plant flowers, numbered 梅=5 蘭=6 菊=7 竹=8

    PIN (筒) TILES — COUNT CIRCLES CAREFULLY
    Pin tiles are the hardest to identify because they differ only in circle count.
    Before naming a pin tile, count the circles one by one:
    - 1p = 1 circle (single large circle)
    - 2p = 2 circles (two stacked)
    - 3p = 3 circles (diagonal line)
    - 4p = 4 circles (2×2 grid)
    - 5p = 5 circles (4 corners + 1 center; X pattern)
    - 6p = 6 circles (2 columns of 3)
    - 7p = 7 circles (top row of 3 + middle row of 2 + bottom row of 2, or similar)
    - 8p = 8 circles (2 columns of 4)
    - 9p = 9 circles (3×3 grid)
    If uncertain between 5/6/7/8/9, recount before committing.

    RULES
    1. Emit rows in top-to-bottom order. Tiles within a row in left-to-right order.
    2. The winning tile IS included in its row's tiles list; do NOT omit it.
    3. List every flower; a complete set has 4 seasons + 4 plants but any subset is valid.
    4. If a tile is partially obscured, use your best guess based on what's visible.
    """
}
