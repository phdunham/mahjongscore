import SwiftUI
import MahjongCore

/// The complete tap-to-enter scoring screen.
public struct HandEntryScreen: View {
    /// `.compact` stacks everything in one scrolling column (iPhone);
    /// `.wide` puts the grid beside the hand/context/score column (Mac).
    public enum Layout {
        case compact
        case wide

        public static var platformDefault: Layout {
            #if os(macOS)
            .wide
            #else
            .compact
            #endif
        }
    }

    @ObservedObject var model: HandEntryModel
    let layout: Layout
    /// Debugging aid: press Score once, shortly after appearing.
    let autoScoreOnAppear: Bool
    @State private var showingTablePayments = false

    // Feedback for the Score button.
    @State private var scoreSucceeded = 0      // haptic trigger
    @State private var scoreFailed = 0         // haptic trigger
    @State private var flashError = false
    @State private var scrollRequest: ScrollRequest?

    private enum Anchor: Hashable { case top, score }

    /// Carries a token so asking for the same anchor twice still fires.
    private struct ScrollRequest: Equatable {
        let anchor: Anchor
        let token = UUID()
    }

    /// Row and section headers stop growing here. They're short labels, and at
    /// the accessibility sizes they'd push the tile grid off the screen. The
    /// context form and score results are left free to scale fully.
    private static let labelTypeCap = DynamicTypeSize.accessibility1

    public init(
        model: HandEntryModel,
        layout: Layout = .platformDefault,
        autoScoreOnAppear: Bool = false
    ) {
        self.model = model
        self.layout = layout
        self.autoScoreOnAppear = autoScoreOnAppear
    }

    public var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingTablePayments = true
                    } label: {
                        // iOS navigation bars reduce a Label to its icon, and a
                        // bare banknote doesn't say "reference sheet" — use words.
                        #if os(iOS)
                        Text("Payments")
                        #else
                        Label("Payments", systemImage: "banknote")
                            .labelStyle(.titleAndIcon)
                        #endif
                    }
                    .help("Dice penalties, flower payouts and other payments outside the winning hand")
                }
            }
            .sheet(isPresented: $showingTablePayments) {
                TablePaymentsView(taiBase: model.taiBase)
            }
            .sensoryFeedback(.success, trigger: scoreSucceeded)
            .sensoryFeedback(.error, trigger: scoreFailed)
            // Every tap that does something gets a tick. A light impact for
            // adding a tile (like a key press); the quieter selection tick for
            // everything else — undo, clear, remove, mark winning, move,
            // selecting a tile, switching rows, opening Payments. Disabled
            // controls never fire, so a dimmed tile stays silent.
            .sensoryFeedback(.impact(weight: .light), trigger: model.tileAddCount)
            .sensoryFeedback(.selection, trigger: model.editCount)
            .sensoryFeedback(.selection, trigger: model.selectedId)
            .sensoryFeedback(.selection, trigger: model.target)
            .sensoryFeedback(.selection, trigger: showingTablePayments)
            .task {
                guard autoScoreOnAppear else { return }
                try? await Task.sleep(for: .milliseconds(600))
                performScore()
            }
    }

    /// Score the hand and react: a valid hand gets a success tap and the view
    /// scrolls to the total; an invalid one gets an error tap, the button
    /// flashes red, and the reason appears right under it.
    private func performScore() {
        withAnimation(.easeOut(duration: 0.2)) { model.score() }
        if model.breakdown != nil {
            scoreSucceeded += 1
            scrollRequest = ScrollRequest(anchor: .score)
        } else {
            scoreFailed += 1
            withAnimation(.easeInOut(duration: 0.12).repeatCount(5, autoreverses: true)) {
                flashError = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(750))
                withAnimation(.easeOut(duration: 0.25)) { flashError = false }
            }
        }
    }

    /// A ScrollView that honours `scrollRequest`.
    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return ScrollViewReader { proxy in
            ScrollView { body }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.anchor, anchor: .top)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .wide:
            HStack(alignment: .top, spacing: 24) {
                scrolling {
                    VStack(alignment: .leading, spacing: 12) {
                        HandStripView(model: model)
                            .id(Anchor.top)
                        actionBar
                        ScoreErrorBanner(model: model)
                        Divider()
                        ContextFormView(model: model)
                        Divider()
                        ScoreResultView(model: model)
                            .id(Anchor.score)
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 400)

                TileGridPicker(model: model)
                    .frame(width: 520)
            }
            .padding(16)
        case .compact:
            // Picker first: it's what you touch for every tile. The hand builds
            // beneath it, then the settings and the result. The action bar is
            // pinned to the bottom edge — thumb reach, and always on screen
            // however long the hand gets — with any scoring error right above
            // it, so the message appears where the button was just pressed.
            scrolling {
                VStack(alignment: .leading, spacing: 12) {
                    TileGridPicker(model: model)
                        .dynamicTypeSize(...Self.labelTypeCap)
                        .id(Anchor.top)
                    HandStripView(model: model)
                        .dynamicTypeSize(...Self.labelTypeCap)
                    Divider()
                    ContextFormView(model: model)
                    Divider()
                    ScoreResultView(model: model)
                        .id(Anchor.score)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    ScoreErrorBanner(model: model)
                    actionBar
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    /// Context-sensitive controls: editing actions when a tile is selected,
    /// otherwise the hand-level actions.
    ///
    /// Must survive large Dynamic Type sizes: labels never wrap, and the bar
    /// steps down (drop the tile count, then icon-only buttons) until it fits.
    /// Text scaling is capped here so the bar can't crowd out the tile grid;
    /// icon-only buttons keep their titles for VoiceOver.
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            actionBarContent(showCount: true).labelStyle(.titleAndIcon)
            actionBarContent(showCount: false).labelStyle(.titleAndIcon)
            actionBarContent(showCount: false).labelStyle(.iconOnly)
        }
        .lineLimit(1)
        .dynamicTypeSize(...Self.labelTypeCap)
        .controlSize(.regular)
    }

    @ViewBuilder
    private func actionBarContent(showCount: Bool) -> some View {
        HStack(spacing: 8) {
            if model.selectedId != nil {
                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                if !model.selectedIsFlower {
                    Button {
                        model.toggleWinningSelected()
                    } label: {
                        Label(
                            model.selectedIsWinning ? "Unmark" : "Winning",
                            systemImage: model.selectedIsWinning ? "star.slash" : "star"
                        )
                    }
                    Button {
                        model.moveSelectedToOtherSection()
                    } label: {
                        Label(
                            model.selectedSection == .concealed ? "To exposed" : "To concealed",
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { model.selectedId = nil }
            } else {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.2)) { model.clearHand() }
                    scrollRequest = ScrollRequest(anchor: .top)   // back to the picker
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .disabled(model.isEmpty)
                Spacer(minLength: 8)
                if showCount {
                    // A winning hand is 17 body tiles (16 + the winning tile),
                    // one more per kong — so this is a count, not a target.
                    Text("\(model.bodyCount) \(model.bodyCount == 1 ? "tile" : "tiles")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(model.bodyCount >= 17 ? .secondary : .tertiary)
                }
                Button {
                    performScore()
                } label: {
                    Label("Score", systemImage: "sparkles")
                        .fontWeight(.semibold)
                }
                .labelStyle(.titleAndIcon)   // the primary action always keeps its title
                .buttonStyle(.borderedProminent)
                .tint(flashError ? .red : nil)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
