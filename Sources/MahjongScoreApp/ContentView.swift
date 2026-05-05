import SwiftUI
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import MahjongCore

struct ContentView: View {

    // MARK: - Persistent session settings

    @AppStorage("taiBase") private var taiBase: Int = 5
    @AppStorage("roundWindRaw") private var roundWindRaw: String = Wind.east.rawValue
    @AppStorage("seatWindRaw") private var seatWindRaw: String = Wind.east.rawValue
    @AppStorage("isDealer") private var isDealer: Bool = false
    @AppStorage("preferredModelRaw") private var preferredModelRaw: String = ClaudeRecognizer.Model.sonnet46.rawValue
    @AppStorage("singleRowIsExposed") private var singleRowIsExposed: Bool = false
    @AppStorage("recognizerModeRaw") private var recognizerModeRaw: String = RecognizerMode.claude.rawValue

    @StateObject private var trainingCoordinator = TrainingCoordinator()
    @State private var showingTraining: Bool = false

    // MARK: - Per-hand state

    @State private var concealed: [IdentifiedTile] = []
    @State private var exposed: [IdentifiedTile] = []
    @State private var flowers: [IdentifiedTile] = []
    @State private var winningTileId: UUID?
    @State private var selectedTileId: UUID?
    @State private var pickerMode: PickerMode?
    @State private var showSingleRowToggle = false

    @State private var selfDrawn = true
    @State private var waitType: WaitType = .openWait
    @State private var autoDetectedWait: WaitType?
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

    @State private var scoreBreakdown: ScoreBreakdown?
    @State private var scoreError: String?
    @State private var recognitionError: String?
    @State private var loggingNotice: String?
    @State private var isRecognizing = false
    @State private var isImporting = false

    @State private var lastPhotoData: Data?
    @State private var lastPhotoMediaType: String = "image/jpeg"
    @State private var lastRecognized: RecognizedTiles?
    @State private var showingPhotoModal: Bool = false

    @State private var showingSettings = false
    @State private var apiKeyInput = ""
    @State private var apiKeyVersion = 0

    // MARK: - Bindings / services

    private var roundWind: Binding<Wind> {
        Binding(
            get: { Wind(rawValue: roundWindRaw) ?? .east },
            set: { roundWindRaw = $0.rawValue }
        )
    }
    private var seatWind: Binding<Wind> {
        Binding(
            get: { Wind(rawValue: seatWindRaw) ?? .east },
            set: { seatWindRaw = $0.rawValue }
        )
    }
    private var preferredModel: Binding<ClaudeRecognizer.Model> {
        Binding(
            get: { ClaudeRecognizer.Model(rawValue: preferredModelRaw) ?? .sonnet46 },
            set: { preferredModelRaw = $0.rawValue }
        )
    }

    private var scorer: Scorer? { try? Scorer.loadDefault() }

    private var recognizerMode: RecognizerMode {
        RecognizerMode(rawValue: recognizerModeRaw) ?? .claude
    }
    private var claudeRecognizer: ClaudeRecognizer? {
        _ = apiKeyVersion
        guard let key = APIKeyStore.resolveAPIKey() else { return nil }
        return ClaudeRecognizer(apiKey: key, model: preferredModel.wrappedValue)
    }
    private var recognizer: ImageRecognizer? {
        switch recognizerMode {
        case .claude:
            return claudeRecognizer
        case .local:
            if let classifier = try? TileClassifier.load() {
                return LocalRecognizer(classifier: classifier, fallback: claudeRecognizer)
            }
            return claudeRecognizer
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: DT.Spacing.sm) {
            topSection
            Divider()
            middleSection
            Divider()
            bottomSection
        }
        .padding(DT.Spacing.md)
        .frame(minWidth: 1180, minHeight: 760)
        .toolbar { toolbarContent }
        .navigationTitle("Mahjong Score")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image]
        ) { result in
            Task { await handlePhoto(result) }
        }
        .sheet(isPresented: $showingSettings) { settingsSheet }
        .sheet(isPresented: $showingTraining) {
            TrainingSheet(coordinator: trainingCoordinator, isPresented: $showingTraining)
        }
        .sheet(item: $pickerMode) { mode in
            tilePickerSheet(for: mode)
        }
        .sheet(isPresented: $showingPhotoModal) {
            photoModal
        }
    }

    @ViewBuilder
    private var photoModal: some View {
        if let data = lastPhotoData, let nsImage = NSImage(data: data) {
            VStack(spacing: DT.Spacing.sm) {
                HStack {
                    Text("Hand photo")
                        .font(.title2).bold()
                    Spacer()
                    Button("Close", role: .cancel) {
                        showingPhotoModal = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .onTapGesture { showingPhotoModal = false }
                    .help("Click photo (or press Esc) to close")
            }
            .padding(DT.Spacing.lg)
            .frame(
                minWidth: 1000, idealWidth: 1280,
                minHeight: 760, idealHeight: 960
            )
        }
    }

    private func tilePickerSheet(for mode: PickerMode) -> some View {
        let isReplace = mode == .replaceSelected
        let selection = isReplace ? currentSelection() : nil

        return TilePickerView(
            title: pickerTitle(for: mode),
            currentTile: selection?.tile,
            isCurrentWinning: selection?.isWinning ?? false,
            onPick: { tile in handlePick(mode: mode, tile: tile) },
            onToggleWinning: (isReplace && (selection?.canBeWinning ?? false))
                ? {
                    toggleWinning()
                    closePicker()
                }
                : nil,
            onDelete: isReplace
                ? {
                    deleteSelected()
                    closePicker()
                }
                : nil,
            onCancel: { closePicker() }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { isImporting = true } label: {
                Label("Load photo…", systemImage: "photo")
            }
            .disabled(isRecognizing || recognizer == nil)
            .help(recognizer == nil ? "Set an API key or train a local model first" : "Load a winning-hand photo")

            if isRecognizing {
                ProgressView().controlSize(.small)
            }

            Picker("Recognizer", selection: Binding(
                get: { recognizerMode },
                set: { recognizerModeRaw = $0.rawValue }
            )) {
                Text("Claude").tag(RecognizerMode.claude)
                Text("Local").tag(RecognizerMode.local)
            }
            .labelsHidden()
            .frame(maxWidth: 120)

            if recognizerMode == .claude {
                Picker("Model", selection: preferredModel) {
                    Text("Sonnet 4.6").tag(ClaudeRecognizer.Model.sonnet46)
                    Text("Opus 4.7").tag(ClaudeRecognizer.Model.opus47)
                    Text("Haiku 4.5").tag(ClaudeRecognizer.Model.haiku45)
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { resetForNewHand() } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Reset this hand")

            Button {
                trainingCoordinator.refreshStats()
                showingTraining = true
            } label: {
                Label("Train", systemImage: "brain")
            }
            .help("Training data status and on-device model training")

            Button {
                apiKeyInput = APIKeyStore.load() ?? ""
                showingSettings = true
            } label: {
                Label("API Key", systemImage: "key")
            }
            .help("Manage API key")
        }
    }

    // MARK: - Top section: photo + tile rows

    private var topSection: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            photoSideView
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                TileRow(
                    label: "Concealed",
                    placeholder: "Load a photo or tap + to add tiles",
                    tiles: $concealed,
                    selectedTileId: selectedTileId,
                    winningTileId: winningTileId,
                    onTileTap: { id in handleTileTap(id) },
                    onAddRequested: { pickerMode = .addToConcealed }
                )
                TileRow(
                    label: "Exposed",
                    placeholder: "Nothing called",
                    tiles: $exposed,
                    selectedTileId: selectedTileId,
                    winningTileId: winningTileId,
                    onTileTap: { id in handleTileTap(id) },
                    onAddRequested: { pickerMode = .addToExposed }
                )
                TileRow(
                    label: "Flowers",
                    placeholder: "No flowers",
                    tiles: $flowers,
                    selectedTileId: selectedTileId,
                    winningTileId: winningTileId,
                    onTileTap: { id in handleTileTap(id) },
                    onAddRequested: { pickerMode = .addToFlowers }
                )
                if showSingleRowToggle {
                    HStack(spacing: DT.Spacing.sm) {
                        Text("Single-row photo:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $singleRowIsExposed) {
                            Text("Concealed").tag(false)
                            Text("Exposed").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                        .onChange(of: singleRowIsExposed) { _, newValue in
                            moveSingleRow(toExposed: newValue)
                        }
                    }
                }
                if let err = recognitionError {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let note = loggingNotice {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    @ViewBuilder
    private var photoSideView: some View {
        let size: CGFloat = 480
        if let data = lastPhotoData, let nsImage = NSImage(data: data) {
            VStack(spacing: 4) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .fill(Color.secondary.opacity(0.05))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .onTapGesture { showingPhotoModal = true }
                    .help("Click to view full size")

                HStack(spacing: 4) {
                    Button {
                        rotatePhoto(clockwise: false)
                    } label: {
                        Image(systemName: "rotate.left")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRecognizing)
                    .help("Rotate counter-clockwise")

                    Button {
                        rotatePhoto(clockwise: true)
                    } label: {
                        Image(systemName: "rotate.right")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRecognizing)
                    .help("Rotate clockwise")

                    Spacer()

                    if isRecognizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await runRecognitionOnCurrentPhoto() }
                        } label: {
                            Label("Recognize", systemImage: "sparkle.magnifyingglass")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(recognizer == nil)
                        .help("Send photo to recognizer")
                    }
                }
                .frame(width: size)

                Text("click photo to enlarge")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: size, alignment: .trailing)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .fill(Color.secondary.opacity(0.06))
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .strokeBorder(
                        Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(recognizer == nil
                         ? "No API key — set one in the toolbar"
                         : "Click to choose a photo")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture {
                if recognizer != nil { isImporting = true }
            }
            .help(recognizer == nil
                  ? "Set an API key in the toolbar before loading a photo"
                  : "Click to choose a photo file")
        }
    }

    // MARK: - Middle section: compact options

    private var middleSection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            // First row: pickers and stepper
            HStack(spacing: DT.Spacing.md) {
                labeledPicker("Round", selection: roundWind) { windOptions }
                labeledPicker("Seat", selection: seatWind) { windOptions }
                labeledPicker("Wait", selection: $waitType) { waitOptions }
                LabeledContent {
                    Stepper(value: $taiBase, in: 0...20) {
                        Text("\(taiBase)").monospacedDigit().frame(minWidth: 18)
                    }
                } label: {
                    Text("Base:").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 120)
                LabeledContent {
                    TextField("", text: $turnsBeforeWin)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                } label: {
                    Text("Turns:").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let auto = autoDetectedWait {
                    Text("wait auto: \(shortWaitLabel(auto))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Toggles in a compact 4-column grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 2
            ) {
                Toggle("Self-drawn 自摸", isOn: $selfDrawn)
                Toggle("Dealer 莊家", isOn: $isDealer)
                Toggle("Ting 聽牌", isOn: $declaredTing)
                Toggle("Last tile 海底", isOn: $lastTile)
                Toggle("After kong 槓上", isOn: $afterKong)
                Toggle("Kong-on-kong 摃上摃", isOn: $afterKongOnKong)
                Toggle("After flower 花上", isOn: $afterFlower)
                Toggle("Robbing kong 搶槓", isOn: $robbingKong)
                Toggle("Heavenly 天胡", isOn: $heavenlyHand)
                Toggle("Earthly 地胡", isOn: $earthlyHand)
                Toggle("Human 人胡", isOn: $humanHand)
            }
            .toggleStyle(.checkbox)
            .font(.callout)
        }
    }

    private func labeledPicker<S: Hashable, C: View>(
        _ label: String,
        selection: Binding<S>,
        @ViewBuilder content: () -> C
    ) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: selection) { content() }
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var windOptions: some View {
        Text("East 東").tag(Wind.east)
        Text("South 南").tag(Wind.south)
        Text("West 西").tag(Wind.west)
        Text("North 北").tag(Wind.north)
    }

    @ViewBuilder
    private var waitOptions: some View {
        Text("Open 兩面").tag(WaitType.openWait)
        Text("Closed 嵌張").tag(WaitType.closedWait)
        Text("Edge 邊張").tag(WaitType.edgeWait)
        Text("Pair 對碰").tag(WaitType.pairWait)
        Text("Single 單釣").tag(WaitType.singleWait)
    }

    // MARK: - Bottom section: total + awards + Score button

    private var bottomSection: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            totalCard
            Divider()
            awardsColumn
            Spacer(minLength: 0)
            scoreButtonColumn
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let breakdown = scoreBreakdown {
                let total = breakdown.totalTai + taiBase
                Text("\(total)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
                Text("台 total").font(.caption).foregroundStyle(.secondary)
                Text("hand \(breakdown.totalTai) · base \(taiBase)")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(scoreError == nil ? "Click Score to tally" : "check errors →")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 140, alignment: .leading)
    }

    private var awardsColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 2) {
                if let err = scoreError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                if let breakdown = scoreBreakdown {
                    Text("\(breakdown.awards.count) patterns")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(
                        breakdown.awards.sorted(by: { $0.totalTai > $1.totalTai }),
                        id: \.ruleId
                    ) { award in
                        HStack(spacing: 6) {
                            Text(award.nameZh)
                                .font(.callout.weight(.medium))
                                .frame(minWidth: 60, alignment: .leading)
                            Text(award.nameEn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(award.count > 1
                                 ? "\(award.taiPerCount)×\(award.count)=\(award.totalTai)"
                                 : "\(award.totalTai)")
                            .font(.callout.monospacedDigit())
                            Text("台")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if scoreBreakdown == nil, scoreError == nil {
                    Text("Mark a winning tile and hit Score to see the breakdown.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, DT.Spacing.sm)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scoreButtonColumn: some View {
        VStack(alignment: .trailing, spacing: DT.Spacing.xs) {
            Button {
                computeScore()
            } label: {
                Label("Score hand", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, DT.Spacing.sm)
                    .padding(.vertical, DT.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
            Text("⌘↩")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 120)
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("API Key").font(.title2).bold()
            Text("Your Anthropic API key is stored in the macOS Keychain. It's used only to recognize tiles from photos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("sk-ant-api03-…", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Delete stored key") {
                    APIKeyStore.clear()
                    apiKeyInput = ""
                    apiKeyVersion += 1
                }
                .disabled(APIKeyStore.load() == nil)
                Spacer()
                Button("Cancel") { showingSettings = false }
                Button("Save") {
                    try? APIKeyStore.save(apiKeyInput)
                    apiKeyVersion += 1
                    showingSettings = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DT.Spacing.lg)
        .frame(minWidth: 480)
    }

    // MARK: - Actions

    @MainActor
    private func handlePhoto(_ result: Result<URL, Error>) async {
        recognitionError = nil
        loggingNotice = nil
        resetForNewHand(preservePhotoState: true)
        switch result {
        case .failure(let error):
            recognitionError = "Failed to open file: \(error.localizedDescription)"
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard let raw = try? Data(contentsOf: url) else {
                recognitionError = "Could not read \(url.lastPathComponent)."
                return
            }
            // Always normalize through a size-bounded JPEG re-encode, regardless
            // of source format. Anthropic's vision API caps images at 5 MB and
            // iPhone photos (HEIC or JPEG) routinely exceed that. Output: JPEG
            // ≤2048 px long edge, quality 0.85 — typically 500 KB–1.5 MB.
            guard let prepared = Self.preparePhotoForAPI(raw) else {
                recognitionError = "Could not decode \(url.lastPathComponent)."
                return
            }
            lastPhotoMediaType = "image/jpeg"
            lastPhotoData = prepared
        }
    }

    /// Decode an arbitrary image format (HEIC/HEIF/JPEG/PNG/TIFF/etc.) and
    /// re-encode as a size-bounded JPEG suitable for Anthropic's 5 MB limit.
    ///
    /// EXIF orientation is read explicitly and baked into the pixels via
    /// `CIImage.oriented(_:)`. The previous approach
    /// (`CGImageSourceCreateThumbnailAtIndex` with the transform flag) is
    /// supposed to handle this but turns out to be unreliable for iPhone
    /// HEIC — HEIF stores orientation slightly differently and the flag
    /// doesn't always honor it. Reading the orientation property and
    /// applying it via Core Image is rock-solid across all 8 orientations.
    private static func preparePhotoForAPI(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        var oriented: CGImage
        if orientation == .up {
            oriented = cgImage
        } else {
            let ci = CIImage(cgImage: cgImage).oriented(orientation)
            let ctx = CIContext()
            oriented = ctx.createCGImage(ci, from: ci.extent) ?? cgImage
        }

        // Belt-and-suspenders: winning-hand photos are always landscape by
        // convention, so if the EXIF path didn't get us there (or the file
        // had no orientation tag at all), rotate 90° CW to land in landscape.
        // Manual rotate buttons let the user fix the direction if needed.
        if oriented.height > oriented.width,
           let landscape = rotateCGImage(oriented, clockwise: true) {
            oriented = landscape
        }

        return encodeBoundedJPEG(oriented)
    }

    /// Rotate a CGImage 90° clockwise or counter-clockwise. Used both by the
    /// auto-orient step in `preparePhotoForAPI` and by the manual rotation
    /// buttons (via `rotateJPEG`).
    private static func rotateCGImage(_ cgImage: CGImage, clockwise: Bool) -> CGImage? {
        let oldW = cgImage.width
        let oldH = cgImage.height
        let newW = oldH
        let newH = oldW
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: newW, height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        let radians: CGFloat = clockwise ? .pi / 2 : -.pi / 2
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -CGFloat(oldW) / 2, y: -CGFloat(oldH) / 2)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: oldW, height: oldH))
        return ctx.makeImage()
    }

    /// Encode a CGImage as JPEG, downscaling to a maximum long-edge dimension
    /// first if needed. Default ceiling: 2048 px / quality 0.85, which keeps
    /// the result well under Anthropic's 5 MB image cap while preserving
    /// enough detail for tile recognition (pin-tile dot counts especially).
    private static func encodeBoundedJPEG(
        _ cgImage: CGImage,
        maxLongEdge: Int = 2048,
        quality: CGFloat = 0.85
    ) -> Data? {
        let w = cgImage.width
        let h = cgImage.height
        let longEdge = max(w, h)

        let toEncode: CGImage
        if longEdge > maxLongEdge {
            let scale = Double(maxLongEdge) / Double(longEdge)
            let newW = max(1, Int(Double(w) * scale))
            let newH = max(1, Int(Double(h) * scale))
            let cs = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: newW, height: newH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: bitmapInfo
            ) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
            guard let scaled = ctx.makeImage() else { return nil }
            toEncode = scaled
        } else {
            toEncode = cgImage
        }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, toEncode, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buffer as Data
    }

    /// Rotate a JPEG 90° clockwise or counter-clockwise. Returns the rotated
    /// JPEG bytes. The whole photo is rotated (not just the displayed copy),
    /// so the same bytes flow on to Claude and the training-data cropper.
    private static func rotateJPEG(_ data: Data, clockwise: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rotated = rotateCGImage(cgImage, clockwise: clockwise)
        else { return nil }
        // Re-encode through the same size-bounded path so a rotated image
        // never grows back over the 5 MB API limit.
        return encodeBoundedJPEG(rotated)
    }

    /// Rotate the loaded photo and re-run recognition (since the previous
    /// bboxes are now stale relative to the rotated image).
    private func rotatePhoto(clockwise: Bool) {
        guard let data = lastPhotoData,
              let rotated = Self.rotateJPEG(data, clockwise: clockwise)
        else { return }
        lastPhotoData = rotated
        // Clear stale recognition state — bboxes no longer apply after rotation.
        lastRecognized = nil
        concealed = []
        exposed = []
        flowers = []
        winningTileId = nil
        selectedTileId = nil
        showSingleRowToggle = false
        scoreBreakdown = nil
        scoreError = nil
        autoDetectedWait = nil
        recognitionError = nil
        loggingNotice = nil
    }

    /// Re-run recognition against the bytes already loaded in `lastPhotoData`.
    /// Used by the rotate action — no file picker, no Claude key check beyond
    /// "is the recognizer configured."
    @MainActor
    private func runRecognitionOnCurrentPhoto() async {
        guard let recognizer, let data = lastPhotoData else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            let recognized = try await recognizer.recognize(imageData: data)
            lastRecognized = recognized
            populateFromRecognition(recognized)
        } catch {
            recognitionError = "Recognition failed: \(error)"
        }
    }

    @MainActor
    private func populateFromRecognition(_ r: RecognizedTiles) {
        concealed = []
        exposed = []
        flowers = []
        winningTileId = nil
        selectedTileId = nil
        showSingleRowToggle = false
        autoDetectedWait = nil

        var seenFlowerTiles = Set<Tile>()
        func addFlower(_ t: RecognizedTile) {
            guard seenFlowerTiles.insert(t.tile).inserted else { return }
            flowers.append(IdentifiedTile(t.tile, bbox: t.bbox, confidence: t.confidence))
        }

        for row in r.rows {
            let allIdTiles = row.tiles.map {
                IdentifiedTile($0.tile, bbox: $0.bbox, confidence: $0.confidence)
            }
            let rowTiles = allIdTiles.filter { !$0.tile.isFlower }
            row.tiles.filter { $0.tile.isFlower }.forEach { addFlower($0) }
            switch row.placement {
            case .upper:
                concealed = rowTiles
            case .lower:
                exposed = rowTiles
            case .single:
                if singleRowIsExposed {
                    exposed = rowTiles
                } else {
                    concealed = rowTiles
                }
                showSingleRowToggle = true
            }
        }
        r.flowers.forEach { addFlower($0) }

        if let w = r.winningTile {
            if let match = concealed.first(where: { $0.tile == w.tile }) {
                winningTileId = match.id
            } else if let match = exposed.first(where: { $0.tile == w.tile }) {
                winningTileId = match.id
            }
        }
    }

    private func moveSingleRow(toExposed: Bool) {
        if toExposed {
            exposed.append(contentsOf: concealed)
            concealed = []
        } else {
            concealed.append(contentsOf: exposed)
            exposed = []
        }
    }

    private func resetForNewHand(preservePhotoState: Bool = false) {
        concealed = []
        exposed = []
        flowers = []
        winningTileId = nil
        selectedTileId = nil
        showSingleRowToggle = false
        waitType = .openWait
        autoDetectedWait = nil
        lastTile = false
        afterKong = false
        afterKongOnKong = false
        afterFlower = false
        robbingKong = false
        declaredTing = false
        heavenlyHand = false
        earthlyHand = false
        humanHand = false
        turnsBeforeWin = ""
        scoreBreakdown = nil
        scoreError = nil
        loggingNotice = nil
        if !preservePhotoState {
            lastPhotoData = nil
            lastRecognized = nil
        }
    }

    private func computeScore() {
        scoreError = nil
        scoreBreakdown = nil
        autoDetectedWait = nil
        loggingNotice = nil

        guard let scorer else {
            scoreError = "Scorer not available — Rules.json failed to load."
            return
        }

        let concealedTiles = concealed.map(\.tile)
        let exposedTiles = exposed.map(\.tile)
        let flowerTiles = flowers.map(\.tile)

        guard flowerTiles.allSatisfy({ $0.isFlower }) else {
            scoreError = "The Flowers row contains non-flower tiles. Fix them before scoring."
            return
        }

        let winning: Tile? = {
            guard let id = winningTileId else { return nil }
            if let t = concealed.first(where: { $0.id == id })?.tile { return t }
            if let t = exposed.first(where: { $0.id == id })?.tile { return t }
            return nil
        }()
        guard let winning else {
            scoreError = "Mark a winning tile first: click a tile and choose 'Mark as winning tile'."
            return
        }

        do {
            let hand = try Decomposer.decomposeWithConcealment(
                concealedTiles: concealedTiles,
                exposedTiles: exposedTiles,
                flowers: flowerTiles,
                winningTile: winning
            )
            let inferred = WaitInference.infer(for: hand)
            waitType = inferred
            autoDetectedWait = inferred

            let ctx = WinContext(
                selfDrawn: selfDrawn,
                isDealer: isDealer,
                roundWind: roundWind.wrappedValue,
                seatWind: seatWind.wrappedValue,
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

            logCorrectionIfApplicable(
                concealedTiles: concealedTiles,
                exposedTiles: exposedTiles,
                flowerTiles: flowerTiles,
                winningTile: winning
            )
        } catch {
            scoreError = "Can't form a valid hand (\(concealedTiles.count) concealed + \(exposedTiles.count) exposed). \(error)"
        }
    }

    private func logCorrectionIfApplicable(
        concealedTiles: [Tile],
        exposedTiles: [Tile],
        flowerTiles: [Tile],
        winningTile: Tile
    ) {
        guard let photoData = lastPhotoData,
              let recognized = lastRecognized else { return }

        var notes: [String] = []
        do {
            try CorrectionsLog.save(
                photoData: photoData,
                photoMediaType: lastPhotoMediaType,
                recognized: recognized,
                correctedConcealed: concealedTiles,
                correctedExposed: exposedTiles,
                correctedFlowers: flowerTiles,
                correctedWinning: winningTile,
                model: preferredModel.wrappedValue.rawValue
            )
            notes.append("log saved")
        } catch {
            notes.append("log failed")
        }

        let allIdTiles = concealed + exposed + flowers
        var labeled: [TrainingDataSaver.LabeledBBox] = []
        var unbboxed = 0
        for idTile in allIdTiles {
            if let bbox = idTile.bbox {
                labeled.append(.init(tile: idTile.tile, bbox: bbox))
            } else {
                unbboxed += 1
            }
        }
        if !labeled.isEmpty {
            let result = TrainingDataSaver.save(
                photoData: photoData,
                labeled: labeled,
                unbboxedLabelCount: unbboxed
            )
            notes.append("+\(result.saved) crops")
        }

        loggingNotice = notes.joined(separator: " · ")
    }

    // MARK: - Selection model + tile editing

    /// Identifies which row a selected tile belongs to.
    private enum TileLocation {
        case concealed(Int)
        case exposed(Int)
        case flowers(Int)
    }

    /// Locate the selected tile by id. Returns nil if the id no longer matches
    /// any tile (which can happen if the array was mutated).
    private func locate(_ id: UUID) -> TileLocation? {
        if let i = concealed.firstIndex(where: { $0.id == id }) { return .concealed(i) }
        if let i = exposed.firstIndex(where: { $0.id == id }) { return .exposed(i) }
        if let i = flowers.firstIndex(where: { $0.id == id }) { return .flowers(i) }
        return nil
    }

    private struct SelectionInfo {
        let id: UUID
        let tile: Tile
        let location: TileLocation
        let isWinning: Bool
        var canBeWinning: Bool {
            // Flowers can't complete a winning hand; only concealed/exposed.
            if case .flowers = location { return false }
            return true
        }
    }

    private func currentSelection() -> SelectionInfo? {
        guard let id = selectedTileId, let loc = locate(id) else { return nil }
        let tile: Tile
        switch loc {
        case .concealed(let i): tile = concealed[i].tile
        case .exposed(let i): tile = exposed[i].tile
        case .flowers(let i): tile = flowers[i].tile
        }
        return SelectionInfo(
            id: id, tile: tile, location: loc,
            isWinning: id == winningTileId
        )
    }

    private func handleTileTap(_ id: UUID) {
        // Click → immediately open the modal picker for that tile.
        // The modal contains the full 42-tile grid plus Mark winning / Delete,
        // so any single click in the modal completes the correction. Two clicks
        // total per correction (tile + chosen action).
        selectedTileId = id
        pickerMode = .replaceSelected
    }

    private func setSelectedTile(_ newTile: Tile) {
        guard let id = selectedTileId, let loc = locate(id) else { return }
        // User has explicitly chosen a tile, so clear any recognizer
        // confidence — the amber low-confidence styling drops away.
        switch loc {
        case .concealed(let i):
            concealed[i].tile = newTile
            concealed[i].confidence = nil
        case .exposed(let i):
            exposed[i].tile = newTile
            exposed[i].confidence = nil
        case .flowers(let i):
            flowers[i].tile = newTile
            flowers[i].confidence = nil
        }
    }

    private func deleteSelected() {
        guard let id = selectedTileId, let loc = locate(id) else { return }
        if winningTileId == id { winningTileId = nil }
        switch loc {
        case .concealed(let i): concealed.remove(at: i)
        case .exposed(let i): exposed.remove(at: i)
        case .flowers(let i): flowers.remove(at: i)
        }
        selectedTileId = nil
    }

    private func toggleWinning() {
        guard let sel = currentSelection(), sel.canBeWinning else { return }
        winningTileId = (winningTileId == sel.id) ? nil : sel.id
    }

    // MARK: - Picker mode (modal sheet)

    enum PickerMode: String, Identifiable {
        case replaceSelected
        case addToConcealed
        case addToExposed
        case addToFlowers
        var id: String { rawValue }
    }

    private func pickerTitle(for mode: PickerMode) -> String {
        switch mode {
        case .replaceSelected: return "Change to…"
        case .addToConcealed: return "Add to Concealed"
        case .addToExposed: return "Add to Exposed"
        case .addToFlowers: return "Add to Flowers"
        }
    }

    private func handlePick(mode: PickerMode, tile: Tile) {
        switch mode {
        case .replaceSelected:
            setSelectedTile(tile)
        case .addToConcealed:
            concealed.append(IdentifiedTile(tile))
        case .addToExposed:
            exposed.append(IdentifiedTile(tile))
        case .addToFlowers:
            flowers.append(IdentifiedTile(tile))
        }
        closePicker()
    }

    private func closePicker() {
        pickerMode = nil
        selectedTileId = nil
    }

    private func shortWaitLabel(_ w: WaitType) -> String {
        switch w {
        case .openWait: "兩面"
        case .closedWait: "嵌張"
        case .edgeWait: "邊張"
        case .pairWait: "對碰"
        case .singleWait: "單釣"
        }
    }
}

#Preview {
    ContentView()
}
