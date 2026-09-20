import SwiftUI
import AppKit

/// Without a real `.app` bundle + Info.plist, macOS launches a SwiftPM executable
/// with an ambiguous activation policy and the SwiftUI window never shows. This
/// delegate forces the regular GUI app behaviour at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Under `swift run` there is no Info.plist to name an icon, so the Dock
        // shows a generic executable. The bundled .app gets AppIcon.icns instead.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
           let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
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
            RootView()
        }
        .defaultSize(width: 1000, height: 760)
    }
}
