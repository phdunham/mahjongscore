import SwiftUI
import AppKit

/// Without a real `.app` bundle + Info.plist, macOS launches a SwiftPM executable
/// with an ambiguous activation policy and the SwiftUI window never shows. This
/// delegate forces the regular GUI app behaviour at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MahjongScoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Mahjong Score") {
            ContentView()
        }
        .defaultSize(width: 820, height: 720)
    }
}
