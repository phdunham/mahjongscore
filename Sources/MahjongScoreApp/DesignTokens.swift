import SwiftUI

/// Compact design tokens for consistent spacing, sizing, and tile rendering.
/// Keeps values in one place so tuning the look-and-feel is a single-file edit.
enum DT {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    enum Tile {
        static let width: CGFloat = 64
        static let height: CGFloat = 88
        static let glyphSize: CGFloat = 50
        static let cornerRadius: CGFloat = 8
        /// Vertical offset applied to the winning tile so it visually half-raises.
        static let winningOffset: CGFloat = -10
        static let border: CGFloat = 1
        static let winningBorder: CGFloat = 2.5
        static let selectedBorder: CGFloat = 2.5
    }
}
