import SwiftUI
import MahjongCore

/// All 42 tile kinds in a nine-column grid. One tap appends a tile to the
/// model. Cells show how many copies are already in the hand and dim when
/// the limit is reached (4 of a body tile, 1 of a flower).
public struct TileGridPicker: View {
    @ObservedObject var model: HandEntryModel

    public init(model: HandEntryModel) {
        self.model = model
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4), count: 9
    )

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Characters 萬", tiles: (1...9).map { Tile.numeric(.man, $0) })
            section("Dots 筒", tiles: (1...9).map { Tile.numeric(.pin, $0) })
            section("Bamboo 條", tiles: (1...9).map { Tile.numeric(.sou, $0) })
            section(
                "Winds and dragons",
                tiles: Wind.allCases.map { Tile.wind($0) } + Dragon.allCases.map { Tile.dragon($0) }
            )
            section("Flowers", tiles: Tile.allFlowers)
        }
    }

    private func section(_ label: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(tiles, id: \.self) { tile in
                    GridTileCell(
                        tile: tile,
                        used: model.usedCount(of: tile),
                        enabled: model.canAdd(tile),
                        action: { model.add(tile) }
                    )
                }
            }
        }
    }
}

struct GridTileCell: View {
    let tile: Tile
    let used: Int
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(TileFace.aspectRatio, contentMode: .fit)
                .overlay(TileFace(tile: tile))
                .overlay(used > 0 ? Color.accentColor.opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            used > 0 ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: used > 0 ? 2 : 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if used > 0 {
                        Text("\(used)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 2, y: -4)
                    }
                }
                .opacity(enabled ? 1 : 0.3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(tile.displayName)
        .accessibilityValue(used > 0 ? "\(used) in hand" : "")
    }
}
