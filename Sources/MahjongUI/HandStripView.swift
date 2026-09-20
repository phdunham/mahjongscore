import SwiftUI
import MahjongCore

/// The tiles entered so far, grouped into Concealed / Exposed / Flowers.
/// Tapping a tile selects it (the action bar then offers remove / mark
/// winning / move). Tapping anywhere else in the Concealed or Exposed region
/// makes that row the target for picker taps.
public struct HandStripView: View {
    @ObservedObject var model: HandEntryModel

    public init(model: HandEntryModel) {
        self.model = model
    }

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 56), spacing: 4)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(.concealed, tiles: model.concealed, placeholder: "Tap a tile to add it")
            row(.exposed, tiles: model.exposed, placeholder: "Nothing called")
            flowersRow
        }
    }

    /// A body row. The whole region — header and tile area — is the tap target
    /// for "send new tiles here", and the chosen row is tinted and outlined so
    /// it's obvious at a glance. (Tiles inside still take their own taps.)
    private func row(_ section: HandSection, tiles: [EntryTile], placeholder: String) -> some View {
        let isTarget = model.target == section
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(section.label)
                    .font(.caption.weight(isTarget ? .semibold : .regular))
                if isTarget {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 9, weight: .bold))
                }
                Text("\(tiles.count)")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.6)
                Spacer(minLength: 0)
                if isTarget {
                    Text("new tiles go here")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isTarget ? Color.accentColor : .secondary)

            tileGrid(tiles, placeholder: placeholder, isTarget: isTarget)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { model.target = section }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.label) row, \(tiles.count) tiles")
        .accessibilityHint(isTarget ? "New tiles go here" : "Double tap to send new tiles here")
        .accessibilityAddTraits(isTarget ? [.isButton, .isSelected] : .isButton)
    }

    /// Flowers aren't a target: a flower tapped in the picker always lands
    /// here, whichever body row is selected.
    private var flowersRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Flowers").font(.caption)
                Text("\(model.flowers.count)")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.6)
                Spacer(minLength: 0)
                Text("added automatically")
                    .font(.caption2)
                    .opacity(0.8)
            }
            .foregroundStyle(.secondary)
            tileGrid(model.flowers, placeholder: "No flowers", isTarget: false)
        }
    }

    private func tileGrid(_ tiles: [EntryTile], placeholder: String, isTarget: Bool) -> some View {
        Group {
            if tiles.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(tiles) { entry in
                        StripTileCell(
                            tile: entry.tile,
                            isWinning: entry.id == model.winningId,
                            isSelected: entry.id == model.selectedId,
                            action: {
                                model.selectedId = (model.selectedId == entry.id) ? nil : entry.id
                            }
                        )
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTarget ? Color.accentColor.opacity(0.10) : PlatformColor.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

struct StripTileCell: View {
    let tile: Tile
    let isWinning: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(TileFace.aspectRatio, contentMode: .fit)
                .overlay(TileFace(tile: tile))
                .overlay(tint)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stroke, lineWidth: lineWidth))
                .overlay(alignment: .topTrailing) {
                    if isWinning {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 4, y: -6)
                    }
                }
                .offset(y: isWinning ? -4 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.displayName)
        .accessibilityValue(isWinning ? "winning tile" : (isSelected ? "selected" : ""))
    }

    private var tint: Color {
        if isSelected { return Color.blue.opacity(0.22) }
        if isWinning { return Color.accentColor.opacity(0.16) }
        return .clear
    }

    private var stroke: Color {
        if isSelected { return .blue }
        if isWinning { return .accentColor }
        return Color.secondary.opacity(0.4)
    }

    private var lineWidth: CGFloat { (isSelected || isWinning) ? 2.5 : 1 }
}
