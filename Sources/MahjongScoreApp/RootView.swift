import SwiftUI
import MahjongUI

/// Top-level mode switch: tap-to-enter grid (default) or the photo
/// recognition pipeline. Both score through the same MahjongCore engine.
struct RootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case enter
        case photo
        var id: String { rawValue }
    }

    @AppStorage("rootMode") private var modeRaw: String = Mode.enter.rawValue
    @StateObject private var entryModel = HandEntryModel()

    private var mode: Binding<Mode> {
        Binding(
            get: { Mode(rawValue: modeRaw) ?? .enter },
            set: { modeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            switch mode.wrappedValue {
            case .enter:
                HandEntryScreen(model: entryModel)
                    .frame(minWidth: 980, minHeight: 720)
                    .navigationTitle("Mahjong Score")
            case .photo:
                ContentView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: mode) {
                    Label("Enter", systemImage: "square.grid.3x3").tag(Mode.enter)
                    Label("Photo", systemImage: "photo").tag(Mode.photo)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Enter tiles by tapping, or recognize them from a photo")
            }
        }
    }
}
