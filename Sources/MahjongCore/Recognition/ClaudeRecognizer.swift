import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Vision-based tile recognizer that calls Anthropic's Messages API.
///
/// Pipeline:
/// 1. **First pass** — send the whole photo, ask for a structured list of
///    tiles, each with notation + bbox + self-rated confidence.
/// 2. **Re-verification** — for each tile flagged uncertain (low confidence,
///    or any pin tile below a high threshold), crop its bbox out of the
///    original image and run a focused single-tile recognition. The cropped
///    pass is much more accurate on dot-counting (the canonical first-pass
///    failure mode for 5p–9p). Replace the label only when the cropped pass
///    is itself confident enough.
///
/// Both passes use `tool_use` for structured output. Confidence values come
/// from Claude's self-assessment — loosely calibrated but useful as a
/// relative routing signal.
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
    public let mediaType: String
    public let session: URLSession
    public let endpoint: URL

    /// Run the focused re-verification pass on uncertain tiles. Each
    /// re-verification is a small extra API call (~$0.005 each at Sonnet
    /// pricing); typically 0–6 fire per hand.
    public var reverifyEnabled: Bool = true

    /// Re-verify any tile below this confidence regardless of family.
    public var reverifyConfidenceThreshold: Double = 0.70

    /// Re-verify pin (筒) tiles below this stricter threshold — pins are the
    /// known weak family for first-pass dot-counting.
    public var reverifyPinsBelow: Double = 0.95

    public init(
        apiKey: String,
        model: Model = .sonnet46,
        mediaType: String = "image/jpeg",
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        reverifyEnabled: Bool = true,
        reverifyConfidenceThreshold: Double = 0.70,
        reverifyPinsBelow: Double = 0.95
    ) {
        self.apiKey = apiKey
        self.model = model
        self.mediaType = mediaType
        self.session = session
        self.endpoint = endpoint
        self.reverifyEnabled = reverifyEnabled
        self.reverifyConfidenceThreshold = reverifyConfidenceThreshold
        self.reverifyPinsBelow = reverifyPinsBelow
    }

    // MARK: - Entry point

    public func recognize(imageData: Data) async throws -> RecognizedTiles {
        let firstPass = try await recognizeWholeImage(imageData: imageData)
        if reverifyEnabled {
            return await reverifyUncertainTiles(firstPass, sourceImage: imageData)
        }
        return firstPass
    }

    // MARK: - First pass: whole image

    private func recognizeWholeImage(imageData: Data) async throws -> RecognizedTiles {
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
        return try Self.toRecognizedTiles(
            dto, rawResponse: String(data: data, encoding: .utf8)
        )
    }

    // MARK: - Second pass: per-tile re-verification

    /// For each uncertain tile in `first`, crop its bbox out of `sourceImage`
    /// and run a focused single-tile recognition. Replace the label when the
    /// cropped pass is confident enough; otherwise keep the original.
    /// Re-verifications run in parallel via TaskGroup.
    private func reverifyUncertainTiles(
        _ first: RecognizedTiles,
        sourceImage: Data
    ) async -> RecognizedTiles {
        guard let cgImage = Self.loadCGImage(from: sourceImage) else { return first }

        // Enumerate every tile in the recognized hand with a path identifier
        // so we can write back to the right slot after parallel calls.
        var jobs: [ReverifyJob] = []
        for (rIdx, row) in first.rows.enumerated() {
            for (tIdx, tile) in row.tiles.enumerated() where shouldReverify(tile) {
                jobs.append(.row(rowIndex: rIdx, tileIndex: tIdx, tile: tile))
            }
        }
        for (idx, flower) in first.flowers.enumerated() where shouldReverify(flower) {
            jobs.append(.flower(index: idx, tile: flower))
        }
        if let w = first.winningTile, shouldReverify(w) {
            jobs.append(.winning(tile: w))
        }
        if jobs.isEmpty { return first }

        // Run in parallel. Each task returns the path it owns + the chosen
        // RecognizedTile (either replaced or original).
        let resolved: [(ReverifyJob, RecognizedTile)] = await withTaskGroup(
            of: (ReverifyJob, RecognizedTile).self
        ) { group in
            for job in jobs {
                group.addTask {
                    let chosen = await self.reverifyOne(
                        original: job.tile, cgImage: cgImage
                    )
                    return (job, chosen)
                }
            }
            var collected: [(ReverifyJob, RecognizedTile)] = []
            for await pair in group { collected.append(pair) }
            return collected
        }

        // Apply updates back into the structure.
        var rows = first.rows
        var flowers = first.flowers
        var winning = first.winningTile
        for (job, newTile) in resolved {
            switch job {
            case .row(let rIdx, let tIdx, _):
                var ts = rows[rIdx].tiles
                ts[tIdx] = newTile
                rows[rIdx] = .init(placement: rows[rIdx].placement, tiles: ts)
            case .flower(let idx, _):
                flowers[idx] = newTile
            case .winning:
                winning = newTile
            }
        }
        return RecognizedTiles(
            rows: rows, flowers: flowers,
            winningTile: winning, rawResponse: first.rawResponse
        )
    }

    private enum ReverifyJob {
        case row(rowIndex: Int, tileIndex: Int, tile: RecognizedTile)
        case flower(index: Int, tile: RecognizedTile)
        case winning(tile: RecognizedTile)

        var tile: RecognizedTile {
            switch self {
            case .row(_, _, let t): return t
            case .flower(_, let t): return t
            case .winning(let t): return t
            }
        }
    }

    /// Decide whether a tile should be re-verified. Pin tiles are checked
    /// strictly; other tiles only when confidence is below the global
    /// threshold. Tiles without a bbox are skipped (we can't crop them).
    private func shouldReverify(_ tile: RecognizedTile) -> Bool {
        guard tile.bbox?.isValid == true else { return false }
        let isPin: Bool = {
            if case .numeric(.pin, _) = tile.tile { return true }
            return false
        }()
        if let conf = tile.confidence {
            if isPin && conf < reverifyPinsBelow { return true }
            return conf < reverifyConfidenceThreshold
        }
        // Confidence missing — re-verify all pins, leave others as-is.
        return isPin
    }

    /// Crop the original tile and run a single-tile recognition. Choose
    /// between the original label and the cropped label based on agreement
    /// and the cropped pass's own confidence.
    private func reverifyOne(
        original: RecognizedTile, cgImage: CGImage
    ) async -> RecognizedTile {
        guard let bbox = original.bbox,
              let cropped = Self.cropAndEncodeJPEG(cgImage: cgImage, bbox: bbox)
        else { return original }

        let candidate: RecognizedTile
        do {
            candidate = try await recognizeSingleTile(croppedImageData: cropped)
        } catch {
            return original
        }
        let candConf = candidate.confidence ?? 0.5

        if candidate.tile == original.tile {
            // Cropped pass agreed — bump confidence to the higher of the two.
            return RecognizedTile(
                tile: original.tile,
                bbox: original.bbox,
                confidence: max(original.confidence ?? 0, candConf)
            )
        }
        // Disagreement: only replace if the cropped pass is itself at least
        // as confident as the routing threshold. Keep the original bbox so
        // the saved training-data crop still maps to the right region.
        if candConf >= reverifyConfidenceThreshold {
            return RecognizedTile(
                tile: candidate.tile,
                bbox: original.bbox,
                confidence: candConf
            )
        }
        return original
    }

    // MARK: - Single-tile call

    /// Run a focused recognition on an already-cropped tile image. Returns
    /// the identified tile + Claude's self-confidence. Used by the
    /// re-verification pipeline; can also be called directly for tools that
    /// already have per-tile crops.
    public func recognizeSingleTile(croppedImageData: Data) async throws -> RecognizedTile {
        let body = Self.singleTileRequestBody(
            model: model,
            mediaType: mediaType,
            base64Image: croppedImageData.base64EncodedString()
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
        let dto = try Self.extractSingleTileToolUse(from: data)
        let trimmed = dto.notation.trimmingCharacters(in: .whitespaces)
        guard let tile = try? Tile(trimmed) else {
            throw RecognitionError.tileParseFailure(notation: dto.notation)
        }
        return RecognizedTile(tile: tile, bbox: nil, confidence: dto.confidence)
    }

    // MARK: - Static helpers — first-pass body / parsing

    static func requestBody(model: Model, mediaType: String, base64Image: String) -> [String: Any] {
        let tileItemSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "notation": [
                    "type": "string",
                    "description": "The tile in ASCII notation (e.g. \"1m\", \"Ew\", \"5f\").",
                ],
                "bbox": [
                    "type": "object",
                    "description": "Normalized [0,1] bounding box with top-left origin.",
                    "properties": [
                        "x": ["type": "number"],
                        "y": ["type": "number"],
                        "width": ["type": "number"],
                        "height": ["type": "number"],
                    ],
                    "required": ["x", "y", "width", "height"],
                ],
                "confidence": [
                    "type": "number",
                    "description": "Self-rated confidence in [0, 1] that the notation is correct.",
                ],
            ],
            "required": ["notation"],
        ]

        return [
            "model": model.rawValue,
            "max_tokens": 4096,
            "tools": [
                [
                    "name": "submit_hand",
                    "description": "Record tiles (with bounding boxes and self-confidence) identified in the photo.",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "rows": [
                                "type": "array",
                                "description": "Body-tile rows in top-to-bottom order. placement: upper, lower, or single.",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "placement": [
                                            "type": "string",
                                            "enum": ["upper", "lower", "single"],
                                        ],
                                        "tiles": [
                                            "type": "array",
                                            "items": tileItemSchema,
                                        ],
                                    ],
                                    "required": ["placement", "tiles"],
                                ],
                            ],
                            "flowers": [
                                "type": "array",
                                "items": tileItemSchema,
                                "description": "Flower tiles visible in the photo.",
                            ],
                            "winning_tile": [
                                "type": "object",
                                "description": "The half-raised winning tile (notation + bbox + confidence).",
                                "properties": [
                                    "notation": ["type": "string"],
                                    "bbox": [
                                        "type": "object",
                                        "properties": [
                                            "x": ["type": "number"],
                                            "y": ["type": "number"],
                                            "width": ["type": "number"],
                                            "height": ["type": "number"],
                                        ],
                                        "required": ["x", "y", "width", "height"],
                                    ],
                                    "confidence": ["type": "number"],
                                ],
                                "required": ["notation"],
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

    struct HandDTO: Decodable {
        struct TileDTO: Decodable {
            let notation: String
            let bbox: BBoxDTO?
            let confidence: Double?
        }
        struct BBoxDTO: Decodable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }
        struct RowDTO: Decodable {
            let placement: String
            let tiles: [TileDTO]
        }
        let rows: [RowDTO]
        let flowers: [TileDTO]
        let winning_tile: TileDTO?
    }

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

    static func toRecognizedTiles(_ dto: HandDTO, rawResponse: String?) throws -> RecognizedTiles {
        var rows: [RecognizedTiles.Row] = []
        for rowDTO in dto.rows {
            guard let placement = RecognizedTiles.Placement(rawValue: rowDTO.placement) else {
                throw RecognitionError.unexpectedResponseShape(
                    "unknown placement '\(rowDTO.placement)'"
                )
            }
            let rts = try rowDTO.tiles.map { try toRecognizedTile($0) }
            rows.append(RecognizedTiles.Row(placement: placement, tiles: rts))
        }
        let flowers = try dto.flowers.map { try toRecognizedTile($0) }

        let winning: RecognizedTile?
        if let w = dto.winning_tile {
            let trimmed = w.notation.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                winning = nil
            } else {
                winning = try? toRecognizedTile(w)
            }
        } else {
            winning = nil
        }

        return RecognizedTiles(
            rows: rows, flowers: flowers,
            winningTile: winning, rawResponse: rawResponse
        )
    }

    private static func toRecognizedTile(_ dto: HandDTO.TileDTO) throws -> RecognizedTile {
        let trimmed = dto.notation.trimmingCharacters(in: .whitespaces)
        guard let tile = try? Tile(trimmed) else {
            throw RecognitionError.tileParseFailure(notation: dto.notation)
        }
        let bbox = dto.bbox.map {
            BBox(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        return RecognizedTile(tile: tile, bbox: bbox, confidence: dto.confidence)
    }

    // MARK: - Static helpers — single-tile body / parsing

    static func singleTileRequestBody(model: Model, mediaType: String, base64Image: String) -> [String: Any] {
        [
            "model": model.rawValue,
            "max_tokens": 256,
            "tools": [
                [
                    "name": "submit_tile",
                    "description": "Identify the single mahjong tile shown in the cropped image.",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "notation": [
                                "type": "string",
                                "description": "The tile in ASCII notation (e.g. \"5p\", \"Ew\").",
                            ],
                            "confidence": [
                                "type": "number",
                                "description": "Self-rated confidence in [0, 1].",
                            ],
                        ],
                        "required": ["notation"],
                    ],
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_tile"],
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
                            "text": singleTilePrompt,
                        ],
                    ],
                ]
            ],
        ]
    }

    struct SingleTileDTO: Decodable {
        let notation: String
        let confidence: Double?
    }

    static func extractSingleTileToolUse(from data: Data) throws -> SingleTileDTO {
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
                return try JSONDecoder().decode(SingleTileDTO.self, from: inputData)
            } catch {
                throw RecognitionError.unexpectedResponseShape("single-tile tool_use decode failed: \(error)")
            }
        }
        throw RecognitionError.noToolUseBlock
    }

    // MARK: - Image helpers (CoreGraphics)

    static func loadCGImage(from imageData: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Crop the source image by `bbox` (with padding) and return JPEG bytes.
    /// The padding gives Claude a bit of context around the tile face.
    static func cropAndEncodeJPEG(
        cgImage: CGImage,
        bbox: BBox,
        paddingFraction: Double = 0.10
    ) -> Data? {
        let imgW = Double(cgImage.width)
        let imgH = Double(cgImage.height)
        let padX = bbox.width * paddingFraction
        let padY = bbox.height * paddingFraction
        let x = max(0, (bbox.x - padX) * imgW)
        let y = max(0, (bbox.y - padY) * imgH)
        let w = min(imgW - x, (bbox.width + 2 * padX) * imgW)
        let h = min(imgH - y, (bbox.height + 2 * padY) * imgH)
        guard w > 8, h > 8 else { return nil }
        guard let cropped = cgImage.cropping(
            to: CGRect(x: x, y: y, width: w, height: h).integral
        ) else { return nil }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, cropped, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buffer as Data
    }

    // MARK: - Convenience

    public static func fromEnvironment(
        model: Model = .sonnet46,
        mediaType: String = "image/jpeg"
    ) -> ClaudeRecognizer? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty
        else { return nil }
        return ClaudeRecognizer(apiKey: key, model: model, mediaType: mediaType)
    }

    // MARK: - Prompts

    public static let recognitionPrompt: String = """
    You are identifying tiles in a photo of a Taiwan 16-tile mahjong winning hand.
    For each tile, report its ASCII notation, its bounding box in the image, AND
    a self-rated confidence in [0, 1].

    LAYOUT
    - ONE or TWO rows of body tiles (flowers are separate).
    - TWO rows: UPPER = concealed hand (placement="upper"), LOWER = exposed /
      called melds (placement="lower").
    - ONE row: placement="single" — concealment decided later by the user.
    - One tile may be visibly HALF-RAISED — that's the WINNING TILE. Include
      it in its row, AND also as winning_tile.
    - FLOWERS are usually off to the side or on top (春夏秋冬 / 梅蘭菊竹).

    BOUNDING BOXES
    - Normalized to [0, 1]. Origin top-left of the image. x/y are the top-left
      of the tile face. Approximate is fine — the app pads before cropping.
    - Omit bbox only if a tile is fully obscured / off-frame.

    CONFIDENCE
    - Set lower (e.g. < 0.7) when you're uncertain — partial occlusion, glare,
      hard-to-count dots. The app re-checks low-confidence tiles via cropped
      single-tile recognition; an honest low confidence is much more useful
      than an overconfident wrong guess.

    TILE NOTATION
    - 1m-9m  : characters (萬)
    - 1p-9p  : dots / circles (筒)
    - 1s-9s  : bamboo (條)
    - Ew, Sw, Ww, Nw : winds (東, 南, 西, 北)
    - Rd, Gd, Wd     : dragons (中, 發, 白)
    - 1f-4f  : season flowers (春=1 夏=2 秋=3 冬=4)
    - 5f-8f  : plant flowers (梅=5 蘭=6 菊=7 竹=8)

    PIN (筒) DOT-COUNTING
    Pin tiles differ only in circle count. Count dots one by one before
    committing, especially 5p–9p:
    - 5p = 5 dots (4 corners + 1 center, X pattern)
    - 6p = 6 dots (2 columns of 3)
    - 7p = 7 dots
    - 8p = 8 dots (2 columns of 4)
    - 9p = 9 dots (3×3 grid)
    If unsure between 5/6/7/8/9, set confidence around 0.6 — the app will
    re-verify with a cropped close-up.

    ORDER
    Rows top-to-bottom; tiles within a row left-to-right.
    """

    public static let singleTilePrompt: String = """
    You are looking at a cropped image of a SINGLE Taiwan mahjong tile.

    Identify it and return the ASCII notation:
    - 1m–9m: characters (萬)
    - 1p–9p: dots / circles (筒) — COUNT the dots carefully (1 through 9)
    - 1s–9s: bamboo (條)
    - Ew, Sw, Ww, Nw: winds (東/南/西/北)
    - Rd, Gd, Wd: dragons (中/發/白)
    - 1f–4f: season flowers (春/夏/秋/冬)
    - 5f–8f: plant flowers (梅/蘭/菊/竹)

    Pin (筒) tiles: count the dots one at a time. The crop should make this
    easier than the wide composite shot. If still unsure between two adjacent
    counts, set confidence accordingly (~0.6) so the app knows the call is shaky.

    Return both `notation` and `confidence` (in [0, 1]).
    """
}
