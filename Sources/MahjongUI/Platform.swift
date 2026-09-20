import SwiftUI

/// Cross-platform colour lookups. SwiftUI's semantic colours differ between
/// AppKit and UIKit, so the few we need are resolved here once.
enum PlatformColor {
    static var tileFace: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var panel: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
