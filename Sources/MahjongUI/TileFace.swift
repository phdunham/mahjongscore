import SwiftUI
import ImageIO
import MahjongCore

/// A tile rendered from the photo of the physical tile (cropped from the
/// cheat-sheet scan by `scripts/extract_tile_images.py`). Fills the frame it
/// is given; callers clip it to a rounded rectangle. Falls back to the
/// Unicode glyph if a photo is missing from the bundle.
public struct TileFace: View {
    let tile: Tile

    public init(tile: Tile) {
        self.tile = tile
    }

    public var body: some View {
        if let cg = TileImageStore.image(for: tile) {
            Image(decorative: cg, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            // U+FE0E forces text presentation: 🀄 (U+1F004) defaults to the
            // colour emoji, unlike the rest of the Mahjong Tiles block.
            Text(tile.unicode + "\u{FE0E}")
                .font(.system(size: 64))
                .minimumScaleFactor(0.2)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(2)
        }
    }

    /// Width ÷ height of the tile photos.
    public static let aspectRatio: CGFloat = 300.0 / 408.0
}

/// Decodes each tile photo once and keeps it for the life of the process.
@MainActor
enum TileImageStore {
    private static var cache: [Tile: CGImage] = [:]
    private static var missing: Set<Tile> = []

    static func image(for tile: Tile) -> CGImage? {
        if let hit = cache[tile] { return hit }
        if missing.contains(tile) { return nil }
        guard let url = Bundle.module.url(forResource: "tile-\(tile.notation)", withExtension: "jpg"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            missing.insert(tile)
            return nil
        }
        cache[tile] = cg
        return cg
    }
}
