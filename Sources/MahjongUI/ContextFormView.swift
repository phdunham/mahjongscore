import SwiftUI
import MahjongCore

/// Win-context inputs. The common ones are always visible; the rare
/// situational bonuses live behind a disclosure so the phone layout stays
/// short.
public struct ContextFormView: View {
    @ObservedObject var model: HandEntryModel
    @State private var showMore: Bool

    public init(model: HandEntryModel, initiallyExpanded: Bool = false) {
        self.model = model
        self._showMore = State(initialValue: initiallyExpanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            windRow("Round", selection: $model.roundWind)
            windRow("Seat", selection: $model.seatWind)

            // Side by side when they fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { winToggles(stacked: false) }
                VStack(alignment: .leading, spacing: 6) { winToggles(stacked: true) }
            }

            DisclosureGroup(isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rare bonuses. Leave them off unless one of these actually happened.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    situationGroup("How the winning tile arrived") {
                        SituationToggle(
                            "Drew the very last tile",
                            detail: "The final tile of the wall completed your hand. Only counts if you drew it yourself.",
                            term: "海底撈月", tai: model.tai(forRule: "last-tile-self-draw"),
                            isOn: $model.lastTile
                        )
                        SituationToggle(
                            "Extra tile after a kong",
                            detail: "You declared a kong (four of a kind), took the extra tile it gives you, and that tile won.",
                            term: "摃上食胡", tai: model.tai(forRule: "win-on-kong"),
                            isOn: $model.afterKong
                        )
                        SituationToggle(
                            "Extra tile after two kongs in a row",
                            detail: "The extra tile from one kong gave you a second kong, and the extra tile from that one won.",
                            term: "摃上摃", tai: model.tai(forRule: "kong-on-kong-win"),
                            isOn: $model.afterKongOnKong
                        )
                        SituationToggle(
                            "Extra tile after a flower",
                            detail: "You drew a flower, took the replacement tile, and that tile won.",
                            term: "花上食胡", tai: model.tai(forRule: "win-on-flower"),
                            isOn: $model.afterFlower
                        )
                        SituationToggle(
                            "Took a tile someone was adding to a kong",
                            detail: "Another player tried to add a fourth tile to their exposed three of a kind, and it was the tile you needed.",
                            term: "搶摃", tai: model.tai(forRule: "robbing-a-kong"),
                            isOn: $model.robbingKong
                        )
                    }

                    situationGroup("Won almost immediately") {
                        SituationToggle(
                            "Dealer, won with the tiles dealt",
                            detail: "You were the dealer and your starting hand was already complete.",
                            term: "天胡", tai: model.tai(forRule: "heavenly-hand"),
                            isOn: $model.heavenlyHand
                        )
                        SituationToggle(
                            "Won on your first draw",
                            detail: "You weren't the dealer, and the first tile you drew from the wall completed your hand.",
                            term: "地胡", tai: model.tai(forRule: "earthly-hand"),
                            isOn: $model.earthlyHand
                        )
                        SituationToggle(
                            "Won within the first four discards",
                            detail: "You weren't the dealer, and you won before more than four tiles had been discarded.",
                            term: "人胡", tai: model.tai(forRule: "human-hand"),
                            isOn: $model.humanHand
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Discards on the table when you won")
                                Spacer(minLength: 8)
                                TextField("–", text: $model.turnsBeforeWin)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                            }
                            Text(discardsHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    situationGroup("Table setting") {
                        VStack(alignment: .leading, spacing: 4) {
                            Stepper(value: $model.taiBase, in: 0...20) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("Base")
                                    Text("\(model.taiBase) 台")
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.tint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("Added to every winning hand, and the size of one 底 on the Payments sheet. Remembered between hands.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Special situations")
            }
            .font(.callout)
        }
        .toggleStyle(.switch)
        .font(.callout)
    }

    private var discardsHint: String {
        let seven = model.tai(forRule: "win-within-seven").map { "+\($0)" } ?? "a bonus"
        let ten = model.tai(forRule: "win-within-ten").map { "+\($0)" } ?? "a smaller bonus"
        return "Count the discarded tiles in the middle, not ones picked up for a chow or pung. "
            + "7 or fewer scores \(seven), 10 or fewer \(ten). Leave blank if there were more. 七只內 / 十只內"
    }

    private func situationGroup<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    /// The everyday switches. When stacked, labels fill the row so the
    /// switches line up on the trailing edge (macOS otherwise parks each
    /// switch right after its text).
    @ViewBuilder
    private func winToggles(stacked: Bool) -> some View {
        winToggle("Self-drawn 自摸", isOn: $model.selfDrawn, fill: stacked)
        winToggle("Dealer 莊家", isOn: $model.isDealer, fill: stacked)
        winToggle("Declared ready 聽牌", isOn: $model.declaredTing, fill: stacked)
            .accessibilityHint("You announced you were one tile from winning, and didn't change your hand after that.")
    }

    private func winToggle(_ title: String, isOn: Binding<Bool>, fill: Bool) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
        }
    }

    private func windRow(_ label: String, selection: Binding<Wind>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(Wind.allCases, id: \.self) { w in
                    Text(w.displayName).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// A switch described by what happened at the table, with the bonus it is
/// worth and the Chinese term (as it appears in the score breakdown).
struct SituationToggle: View {
    let title: String
    let detail: String
    let term: String
    let tai: Int?
    @Binding var isOn: Bool

    init(_ title: String, detail: String, term: String, tai: Int?, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.term = term
        self.tai = tai
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                    if let tai {
                        Text("+\(tai)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                }
                Text("\(detail) \(term)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Fill the row so every switch lines up on the trailing edge
            // (macOS otherwise parks the switch right after the text).
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
