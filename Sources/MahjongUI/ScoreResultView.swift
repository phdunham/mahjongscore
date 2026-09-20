import SwiftUI
import MahjongCore

/// Total tai plus the list of awarded patterns. (A scoring error is shown by
/// `ScoreErrorBanner`, next to the Score button, not down here.)
public struct ScoreResultView: View {
    @ObservedObject var model: HandEntryModel

    public init(model: HandEntryModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let b = model.breakdown {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(b.totalTai + model.taiBase)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                    Text("台")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("hand \(b.totalTai) · base \(model.taiBase)")
                        if let w = model.inferredWait {
                            Text("wait: \(waitLabel(w))")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }

                if b.awards.isEmpty {
                    Text("No patterns — chicken hand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(b.awards.sorted { $0.totalTai > $1.totalTai }, id: \.ruleId) { a in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                // One flowing piece of text: the Chinese name, then
                                // the English explanation, wrapping onto further
                                // lines as needed — never cut off with "…".
                                (Text(a.nameZh).font(.callout.weight(.medium))
                                 + Text("  ")
                                 + Text(a.nameEn).font(.caption).foregroundStyle(.secondary))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 4)
                                Text(a.count > 1 ? "\(a.taiPerCount)×\(a.count)=\(a.totalTai)" : "\(a.totalTai)")
                                    .font(.callout.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }

    private func waitLabel(_ w: WaitType) -> String {
        switch w {
        case .openWait: "兩面"
        case .closedWait: "嵌張"
        case .edgeWait: "邊張"
        case .pairWait: "對碰"
        case .singleWait: "單釣"
        }
    }
}

/// Why the hand couldn't be scored. Lives directly under the Score button so
/// it's on screen at the moment the button is pressed.
public struct ScoreErrorBanner: View {
    @ObservedObject var model: HandEntryModel

    public init(model: HandEntryModel) {
        self.model = model
    }

    public var body: some View {
        if let err = model.scoreError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(err)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
        }
    }
}
