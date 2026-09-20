import SwiftUI
import MahjongCore
import MahjongUI

@main
struct MahjongScoreiOSApp: App {
    @StateObject private var model = HandEntryModel()

    /// DEBUG launch arguments, for checking the screen on a simulator without
    /// tapping through it:
    ///   -sampleHand    pre-fill a valid 17-tile hand
    ///   -invalidHand   pre-fill tiles that don't make a hand
    ///   -autoScore     press Score automatically just after launch
    private let autoScore: Bool

    init() {
        var auto = false
        #if DEBUG
        let args = CommandLine.arguments
        auto = args.contains("-autoScore")
        if args.contains("-sampleHand") || args.contains("-invalidHand") {
            let m = HandEntryModel()
            m.target = .exposed
            for n in ["5p", "5p", "5p"] { m.add(try! Tile(n)) }
            m.target = .concealed
            let body = args.contains("-invalidHand")
                ? ["1m", "2m", "4m", "1p", "1p", "9p", "1s", "2s", "3s", "Ew", "Ew", "Sw", "Nw", "Nw"]
                : ["1m", "2m", "3m", "1p", "1p", "1p", "1s", "2s", "3s", "Ew", "Ew", "Ew", "Nw", "Nw"]
            for n in body { m.add(try! Tile(n)) }
            m.add(try! Tile("1f"))
            _model = StateObject(wrappedValue: m)
        }
        #endif
        autoScore = auto
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HandEntryScreen(model: model, autoScoreOnAppear: autoScore)
                    .navigationTitle("Mahjong Score")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
