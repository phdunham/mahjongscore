import SwiftUI
import MahjongCore

/// Reference sheet: payments made at the table that aren't part of scoring a
/// winning hand (dice penalties, flower-set payouts, procedural penalties).
/// Amounts are defined in bases (底), so they follow the Base setting.
public struct TablePaymentsView: View {
    let taiBase: Int
    @Environment(\.dismiss) private var dismiss

    public init(taiBase: Int) {
        self.taiBase = taiBase
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                TablePaymentsList(taiBase: taiBase)
                    .padding(16)
            }
            .navigationTitle("Table payments")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 720)
        #endif
    }
}

/// The scroll-free content of the sheet (also what SnapshotUI renders).
public struct TablePaymentsList: View {
    let taiBase: Int
    private let payments: [TablePayment]

    public init(taiBase: Int) {
        self.taiBase = taiBase
        self.payments = (try? TablePayments.load()) ?? []
    }

    /// Groups in file order.
    private var groups: [(name: String, items: [TablePayment])] {
        var order: [String] = []
        var byGroup: [String: [TablePayment]] = [:]
        for p in payments {
            if byGroup[p.group] == nil { order.append(p.group) }
            byGroup[p.group, default: []].append(p)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paid on the spot, separately from the winning hand.")
                    .font(.callout)
                Text("Amounts are set in bases (底). With your Base at \(taiBase) 台, 1 底 = \(taiBase) 台. Change Base under Special situations and these follow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            if payments.isEmpty {
                Text("The table-payments list couldn't be loaded.")
                    .foregroundStyle(.red)
            }

            ForEach(groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(group.items) { payment in
                        TablePaymentRow(payment: payment, taiBase: taiBase)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TablePaymentRow: View {
    let payment: TablePayment
    let taiBase: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(payment.title)
                    .font(.body.weight(.semibold))
                Text(payment.nameZh)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(payment.when)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(amountEach)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(direction)
                        .font(.callout)
                    if let detail = amountDetail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)

            if let note = payment.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.09)))
        .accessibilityElement(children: .combine)
    }

    /// "5 台" — the size of one payment.
    private var amountEach: String {
        "\(Self.format(payment.taiEach(base: taiBase))) 台"
    }

    /// "The dealer pays each other player"
    private var direction: String {
        if let receiver = payment.receiver {
            return "\(payment.payer) pays \(receiver)"
        }
        return "\(payment.payer) pays"
    }

    /// "1 底 each · 15 台 changes hands in total"
    private var amountDetail: String? {
        var parts: [String] = []
        if let bases = payment.basesEach {
            parts.append("\(Self.format(bases)) 底\(payment.payments > 1 ? " each" : "")")
        } else {
            parts.append("flat amount")
        }
        if payment.payments > 1 {
            parts.append("\(Self.format(payment.taiTotal(base: taiBase))) 台 in total")
        }
        return parts.joined(separator: " · ")
    }

    /// 5 → "5", 2.5 → "2.5", 0.5 → "½" is avoided: keep digits for clarity.
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
