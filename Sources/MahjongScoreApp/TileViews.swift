import SwiftUI
import MahjongCore

// MARK: - Identified tile model

/// A tile with a stable identity independent of its `Tile` value. Needed because
/// a hand can have duplicate tile values (e.g. a pung of 5p) and we still have
/// to point at a specific one when the user taps it or marks it as the winning tile.
///
/// Carries the optional `bbox` from recognition so we can crop training samples
/// from the source photo on successful scoring. Replacing the tile via the
/// picker keeps the bbox intact (same physical tile, corrected label).
struct IdentifiedTile: Identifiable, Hashable {
    let id: UUID
    var tile: Tile
    var bbox: BBox?

    init(_ tile: Tile, bbox: BBox? = nil, id: UUID = UUID()) {
        self.id = id
        self.tile = tile
        self.bbox = bbox
    }
}

// MARK: - TileCard

/// A single tile face. Click selects it; the action toolbar at the
/// ContentView level handles editing and the modal picker handles
/// arbitrary tile changes. There is no per-card menu anymore.
struct TileCard: View {
    let tile: Tile
    let isWinning: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardFace
        }
        .buttonStyle(.plain)
    }

    private var cardFace: some View {
        ZStack(alignment: .topTrailing) {
            Text(tile.unicode)
                .font(.system(size: DT.Tile.glyphSize))
                .foregroundStyle(.primary)
                .frame(width: DT.Tile.width, height: DT.Tile.height)
                .background(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    x: 0,
                    y: isWinning ? 2 : 0
                )

            if isWinning {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(
                        Circle().strokeBorder(
                            Color(nsColor: .controlBackgroundColor),
                            lineWidth: 1.5
                        )
                    )
                    .offset(x: 7, y: -7)
            }
        }
        .offset(y: isWinning ? DT.Tile.winningOffset : 0)
        .help(helpText)
    }

    private var backgroundFill: Color {
        if isWinning { return Color.accentColor.opacity(0.22) }
        if isSelected { return Color.blue.opacity(0.18) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isWinning { return Color.accentColor }
        if isSelected { return Color.blue }
        return Color.secondary.opacity(0.35)
    }

    private var borderWidth: CGFloat {
        if isWinning { return DT.Tile.winningBorder }
        if isSelected { return DT.Tile.selectedBorder }
        return DT.Tile.border
    }

    private var shadowColor: Color {
        if isWinning { return Color.accentColor.opacity(0.45) }
        return .clear
    }

    private var shadowRadius: CGFloat {
        isWinning ? 6 : 0
    }

    private var helpText: String {
        if isWinning { return "\(tile.displayName) — winning tile" }
        if isSelected { return "\(tile.displayName) — selected" }
        return tile.displayName
    }
}

// MARK: - AddTileButton

/// "+" placeholder at the end of a row. Click opens the modal flat picker
/// to choose a tile to append.
struct AddTileButton: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: DT.Tile.width, height: DT.Tile.height)
                .background(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .strokeBorder(
                            Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Add a tile")
    }
}

// MARK: - TileRow

/// A labeled horizontal row of tile cards plus an add button. Selection and
/// editing are handled by the parent — this view just renders state and
/// reports taps via the callbacks.
struct TileRow: View {
    let label: String
    let placeholder: String?
    @Binding var tiles: [IdentifiedTile]
    let selectedTileId: UUID?
    let winningTileId: UUID?
    let onTileTap: (UUID) -> Void
    let onAddRequested: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DT.Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.xs) {
                    ForEach(tiles) { idTile in
                        TileCard(
                            tile: idTile.tile,
                            isWinning: idTile.id == winningTileId,
                            isSelected: idTile.id == selectedTileId,
                            onTap: { onTileTap(idTile.id) }
                        )
                    }
                    AddTileButton(onAdd: onAddRequested)

                    if tiles.isEmpty, let placeholder {
                        Text(placeholder)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, DT.Spacing.sm)
                    }
                }
                .padding(.top, abs(DT.Tile.winningOffset))
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - TilePickerView

/// Modal sheet that shows all 42 tile types in one flat grid. Picking any
/// tile invokes `onPick` and closes. When `currentTile` is non-nil (edit mode),
/// optional `onToggleWinning` and `onDelete` actions are also shown — clicking
/// either runs the action and closes. Two clicks total for any correction.
struct TilePickerView: View {
    let title: String
    let currentTile: Tile?
    let isCurrentWinning: Bool
    let onPick: (Tile) -> Void
    let onToggleWinning: (() -> Void)?
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            header
            section(label: "Numbers (萬)", tiles: numericTiles(.man))
            section(label: "Dots (筒)", tiles: numericTiles(.pin))
            section(label: "Sticks (條)", tiles: numericTiles(.sou))
            HStack(alignment: .top, spacing: DT.Spacing.lg) {
                section(label: "Winds", tiles: Wind.allCases.map { Tile.wind($0) })
                section(label: "Dragons", tiles: Dragon.allCases.map { Tile.dragon($0) })
            }
            HStack(alignment: .top, spacing: DT.Spacing.lg) {
                section(
                    label: "Seasons (春夏秋冬)",
                    tiles: (1...4).map { Tile.flower(Flower(kind: .season, index: $0)!) }
                )
                section(
                    label: "Plants (梅蘭菊竹)",
                    tiles: (1...4).map { Tile.flower(Flower(kind: .plant, index: $0)!) }
                )
            }
            if onToggleWinning != nil || onDelete != nil {
                Divider()
                HStack(spacing: DT.Spacing.md) {
                    if let toggle = onToggleWinning {
                        Button(action: toggle) {
                            Label(
                                isCurrentWinning ? "Unmark winning" : "Mark winning",
                                systemImage: isCurrentWinning ? "star.slash" : "star"
                            )
                            .padding(.horizontal, DT.Spacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    if let delete = onDelete {
                        Button(role: .destructive, action: delete) {
                            Label("Delete tile", systemImage: "trash")
                                .padding(.horizontal, DT.Spacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    Spacer()
                }
            }
        }
        .padding(DT.Spacing.lg)
        .frame(minWidth: 700, minHeight: 660)
    }

    private var header: some View {
        HStack(spacing: DT.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2).bold()
                if let current = currentTile {
                    HStack(spacing: 6) {
                        Text("Current:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(current.unicode)
                            .font(.system(size: 24))
                        Text(current.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        if isCurrentWinning {
                            Label("winning", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func numericTiles(_ suit: Suit) -> [Tile] {
        (1...9).map { Tile.numeric(suit, $0) }
    }

    private func section(label: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: DT.Spacing.xs) {
                ForEach(tiles, id: \.self) { tile in
                    PickerTile(
                        tile: tile,
                        isCurrent: tile == currentTile,
                        onPick: { onPick(tile) }
                    )
                }
            }
        }
    }
}

private struct PickerTile: View {
    let tile: Tile
    let isCurrent: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            Text(tile.unicode)
                .font(.system(size: DT.Tile.glyphSize))
                .foregroundStyle(.primary)
                .frame(width: DT.Tile.width, height: DT.Tile.height)
                .background(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .fill(isCurrent
                              ? Color.accentColor.opacity(0.15)
                              : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Tile.cornerRadius)
                        .strokeBorder(
                            isCurrent ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isCurrent ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(isCurrent ? "\(tile.displayName) — current" : tile.displayName)
    }
}
