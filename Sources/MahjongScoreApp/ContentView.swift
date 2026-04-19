import SwiftUI
import UniformTypeIdentifiers
import MahjongCore

struct ContentView: View {

    // MARK: - Tile state

    /// Upper row from the photo (user convention: concealed hand).
    @State private var concealedText: String = ""
    /// Lower row from the photo (user convention: exposed / called melds).
    @State private var exposedText: String = ""
    @State private var flowersText: String = ""
    @State private var winningTileText: String = ""

    /// When the photo had a single row, this is the placement the user chose for
    /// those tiles (concealed by default). Toggling moves them between fields.
    @State private var singleRowIsExposed: Bool = false
    /// True when the last recognition returned a single-row photo; shows the toggle.
    @State private var showSingleRowToggle: Bool = false

    // MARK: - Win context state

    @State private var selfDrawn = true
    @State private var isDealer = false
    @State private var roundWind: Wind = .east
    @State private var seatWind: Wind = .east
    @State private var waitType: WaitType = .openWait
    @State private var autoDetectedWait: WaitType?   // shown next to picker for context
    @State private var lastTile = false
    @State private var afterKong = false
    @State private var afterKongOnKong = false
    @State private var afterFlower = false
    @State private var robbingKong = false
    @State private var declaredTing = false
    @State private var heavenlyHand = false
    @State private var earthlyHand = false
    @State private var humanHand = false
    @State private var turnsBeforeWin: String = ""
    @State private var taiFloor: Int = 5

    // MARK: - Result state

    @State private var scoreBreakdown: ScoreBreakdown?
    @State private var scoreError: String?
    @State private var recognitionError: String?
    @State private var isRecognizing = false
    @State private var isImporting = false

    // MARK: - Services

    private let recognizer: ImageRecognizer? = ClaudeRecognizer.fromEnvironment()
    private let scorer: Scorer? = try? Scorer.loadDefault()

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                photoSection
                tilesSection
                contextSection
                scoreSection
            }
            .padding(24)
        }
        .frame(minWidth: 780, minHeight: 640)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image]
        ) { result in
            Task { await handlePhoto(result) }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mahjong Score").font(.largeTitle).bold()
            Text("Upper row = concealed, lower row = exposed. The half-raised tile is the winner.")
                .foregroundStyle(.secondary)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { isImporting = true } label: {
                    Label("Load photo…", systemImage: "photo")
                }
                .disabled(isRecognizing || recognizer == nil)
                if isRecognizing {
                    ProgressView().controlSize(.small)
                    Text("Recognizing…").foregroundStyle(.secondary)
                }
                Spacer()
            }
            if recognizer == nil {
                Text("ANTHROPIC_API_KEY not set — photo recognition disabled. Enter tiles manually below.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let err = recognitionError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var tilesSection: some View {
        GroupBox("Tiles") {
            VStack(alignment: .leading, spacing: 10) {
                tileField(label: "Concealed (upper row)", text: $concealedText,
                          placeholder: "1m 2m 3m 4m 5m 6m 7p 8p 9p 1s 2s 3s 3s 3s")
                glyphPreview(concealedText)

                tileField(label: "Exposed (lower row)", text: $exposedText,
                          placeholder: "5p 5p 5p (empty if nothing called)")
                glyphPreview(exposedText)

                if showSingleRowToggle {
                    HStack {
                        Text("Single-row photo — treat as:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $singleRowIsExposed) {
                            Text("Concealed").tag(false)
                            Text("Exposed").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        .onChange(of: singleRowIsExposed) { _, newValue in
                            moveSingleRow(toExposed: newValue)
                        }
                    }
                    .padding(.vertical, 4)
                }

                tileField(label: "Flowers", text: $flowersText, placeholder: "1f 6f")
                glyphPreview(flowersText)

                tileField(label: "Winning tile", text: $winningTileText,
                          placeholder: "3s", maxWidth: 140)
            }
            .padding(.vertical, 4)
        }
    }

    private func tileField(label: String, text: Binding<String>, placeholder: String, maxWidth: CGFloat? = nil) -> some View {
        LabeledContent(label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: maxWidth)
        }
    }

    @ViewBuilder
    private func glyphPreview(_ text: String) -> some View {
        let parsed = parseTiles(text)
        if !parsed.tiles.isEmpty || !parsed.unknown.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if !parsed.tiles.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(parsed.tiles.enumerated()), id: \.offset) { _, tile in
                            Text(tile.unicode).font(.system(size: 28))
                        }
                    }
                }
                if !parsed.unknown.isEmpty {
                    Text("Unknown: \(parsed.unknown.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var contextSection: some View {
        GroupBox("Win context") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Stepper(value: $taiFloor, in: 0...20) {
                        Text("Tai floor (table rule): **\(taiFloor)**")
                    }
                    .help("Minimum tai paid out regardless of actual score.")
                    Spacer()
                }
                Divider()
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    Toggle("Self-drawn (自摸)", isOn: $selfDrawn)
                    Toggle("Dealer (莊家)", isOn: $isDealer)
                    Picker("Round wind", selection: $roundWind) { windOptions }
                    Picker("Seat wind", selection: $seatWind) { windOptions }
                    waitTypePicker
                    LabeledContent("Turns before win") {
                        TextField("optional", text: $turnsBeforeWin)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 80)
                    }
                    Toggle("Declared ready (聽牌)", isOn: $declaredTing)
                Toggle("Last tile (海底)", isOn: $lastTile)
                Toggle("After kong (槓上開花)", isOn: $afterKong)
                Toggle("Kong on kong (摃上摃)", isOn: $afterKongOnKong)
                Toggle("After flower (花上食胡)", isOn: $afterFlower)
                Toggle("Robbing kong (搶槓)", isOn: $robbingKong)
                    Toggle("Heavenly hand (天胡)", isOn: $heavenlyHand)
                    Toggle("Earthly hand (地胡)", isOn: $earthlyHand)
                    Toggle("Human hand (人胡)", isOn: $humanHand)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var waitTypePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Wait type", selection: $waitType) {
                Text("Open (兩面)").tag(WaitType.openWait)
                Text("Closed (嵌張)").tag(WaitType.closedWait)
                Text("Edge (邊張)").tag(WaitType.edgeWait)
                Text("Pair (對碰)").tag(WaitType.pairWait)
                Text("Single (單釣)").tag(WaitType.singleWait)
            }
            if let auto = autoDetectedWait {
                Text("auto-detected: \(waitTypeLabel(auto))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var windOptions: some View {
        Text("East (東)").tag(Wind.east)
        Text("South (南)").tag(Wind.south)
        Text("West (西)").tag(Wind.west)
        Text("North (北)").tag(Wind.north)
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { computeScore() } label: {
                    Label("Score hand", systemImage: "sparkles")
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                Spacer()
                if let breakdown = scoreBreakdown {
                    let effective = max(breakdown.totalTai, taiFloor)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Pays: \(effective) 台")
                            .font(.title).bold()
                            .foregroundStyle(.tint)
                            .monospacedDigit()
                        if effective != breakdown.totalTai {
                            Text("actual \(breakdown.totalTai) 台 · floor \(taiFloor) 台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("actual \(breakdown.totalTai) 台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let scoreError {
                Text(scoreError).foregroundStyle(.red)
            }
            if let breakdown = scoreBreakdown {
                GroupBox("Breakdown (\(breakdown.awards.count) awards)") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(
                            breakdown.awards.sorted(by: { $0.totalTai > $1.totalTai }),
                            id: \.ruleId
                        ) { award in
                            HStack {
                                Text(award.nameZh).font(.body.monospacedDigit())
                                Text("  \(award.nameEn)").foregroundStyle(.secondary)
                                Spacer()
                                Text(award.count > 1
                                     ? "\(award.taiPerCount) × \(award.count) = \(award.totalTai) 台"
                                     : "\(award.totalTai) 台")
                                .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func handlePhoto(_ result: Result<URL, Error>) async {
        recognitionError = nil
        switch result {
        case .failure(let error):
            recognitionError = "Failed to open file: \(error.localizedDescription)"
        case .success(let url):
            guard let recognizer else {
                recognitionError = "No recognizer configured."
                return
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else {
                recognitionError = "Could not read \(url.lastPathComponent)."
                return
            }
            isRecognizing = true
            defer { isRecognizing = false }
            do {
                let recognized = try await recognizer.recognize(imageData: data)
                populateFromRecognition(recognized)
            } catch {
                recognitionError = "Recognition failed: \(error)"
            }
        }
    }

    @MainActor
    private func populateFromRecognition(_ r: RecognizedTiles) {
        // Reset everything fresh.
        concealedText = ""
        exposedText = ""
        flowersText = ""
        winningTileText = ""
        showSingleRowToggle = false
        autoDetectedWait = nil

        for row in r.rows {
            let text = row.tiles.map(\.notation).joined(separator: " ")
            switch row.placement {
            case .upper:
                concealedText = text
            case .lower:
                exposedText = text
            case .single:
                // Default the single row into whichever bucket the toggle says.
                if singleRowIsExposed {
                    exposedText = text
                } else {
                    concealedText = text
                }
                showSingleRowToggle = true
            }
        }
        flowersText = r.flowers.map(\.notation).joined(separator: " ")
        if let w = r.winningTile {
            winningTileText = w.notation
        }
    }

    /// Move the single-row tiles between the concealed and exposed fields.
    private func moveSingleRow(toExposed: Bool) {
        if toExposed {
            // Move concealed → exposed, keeping anything already in exposed.
            let movedText = concealedText
            concealedText = ""
            exposedText = [exposedText, movedText]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: " ")
        } else {
            let movedText = exposedText
            exposedText = ""
            concealedText = [concealedText, movedText]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: " ")
        }
    }

    private func computeScore() {
        scoreError = nil
        scoreBreakdown = nil
        autoDetectedWait = nil

        guard let scorer else {
            scoreError = "Scorer not available — Rules.json failed to load."
            return
        }

        let concealed = parseTiles(concealedText)
        guard concealed.unknown.isEmpty else {
            scoreError = "Unknown concealed tiles: \(concealed.unknown.joined(separator: ", "))"
            return
        }
        let exposed = parseTiles(exposedText)
        guard exposed.unknown.isEmpty else {
            scoreError = "Unknown exposed tiles: \(exposed.unknown.joined(separator: ", "))"
            return
        }
        let flowers = parseTiles(flowersText)
        guard flowers.unknown.isEmpty else {
            scoreError = "Unknown flower tiles: \(flowers.unknown.joined(separator: ", "))"
            return
        }
        let winningTrimmed = winningTileText.trimmingCharacters(in: .whitespaces)
        guard !winningTrimmed.isEmpty,
              let winning = try? Tile(winningTrimmed)
        else {
            scoreError = "Enter the winning tile (e.g. '3s')."
            return
        }

        do {
            let hand = try Decomposer.decomposeWithConcealment(
                concealedTiles: concealed.tiles,
                exposedTiles: exposed.tiles,
                flowers: flowers.tiles,
                winningTile: winning
            )
            // Auto-infer wait type and overwrite the picker.
            let inferred = WaitInference.infer(for: hand)
            waitType = inferred
            autoDetectedWait = inferred

            let ctx = WinContext(
                selfDrawn: selfDrawn,
                isDealer: isDealer,
                roundWind: roundWind,
                seatWind: seatWind,
                waitType: inferred,
                lastTile: lastTile,
                afterKong: afterKong,
                afterKongOnKong: afterKongOnKong,
                afterFlower: afterFlower,
                robbingKong: robbingKong,
                heavenlyHand: heavenlyHand,
                earthlyHand: earthlyHand,
                humanHand: humanHand,
                declaredTing: declaredTing,
                turnsBeforeWin: Int(turnsBeforeWin.trimmingCharacters(in: .whitespaces))
            )
            scoreBreakdown = scorer.score(hand: hand, context: ctx)
        } catch {
            scoreError = "Can't form a valid hand (\(concealed.tiles.count) concealed + \(exposed.tiles.count) exposed). \(error)"
        }
    }

    private func parseTiles(_ s: String) -> (tiles: [Tile], unknown: [String]) {
        var tiles: [Tile] = []
        var unknown: [String] = []
        for raw in s.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            let token = String(raw)
            if token.isEmpty { continue }
            if let tile = try? Tile(token) {
                tiles.append(tile)
            } else {
                unknown.append(token)
            }
        }
        return (tiles, unknown)
    }

    private func waitTypeLabel(_ w: WaitType) -> String {
        switch w {
        case .openWait: "Open (兩面)"
        case .closedWait: "Closed (嵌張)"
        case .edgeWait: "Edge (邊張)"
        case .pairWait: "Pair (對碰)"
        case .singleWait: "Single (單釣)"
        }
    }
}

#Preview {
    ContentView()
}
