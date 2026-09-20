import Foundation

/// A payment made at the table that isn't part of scoring a winning hand —
/// dice penalties, flower-set payouts, procedural penalties. Loaded from
/// `TablePayments.json`, kept separate from `Rules.json` so the scoring rule
/// table is never disturbed by reference data.
public struct TablePayment: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    /// Matching entry in `Rules.json`, where one exists.
    public let ruleId: String?
    public let group: String
    public let nameZh: String
    public let title: String
    public let when: String
    public let payer: String
    /// `nil` when the source rule doesn't say who receives the payment.
    public let receiver: String?
    /// Size of each payment in bases (底). `nil` for flat-amount penalties.
    public let basesEach: Double?
    /// How many such payments change hands (3 when "each other player").
    public let payments: Int
    /// Flat amount in tai, for penalties not tied to the base.
    public let fixedTai: Int?
    public let note: String?

    /// Tai per individual payment, given the table's base (tai per 底).
    public func taiEach(base: Int) -> Double {
        if let fixedTai { return Double(fixedTai) }
        return (basesEach ?? 0) * Double(base)
    }

    /// Total tai changing hands across all the payments.
    public func taiTotal(base: Int) -> Double {
        taiEach(base: base) * Double(payments)
    }
}

public enum TablePayments {
    public enum LoadError: Error, Equatable {
        case resourceMissing
    }

    private struct File: Codable {
        let payments: [TablePayment]
    }

    public static func load() throws -> [TablePayment] {
        guard let url = Bundle.module.url(forResource: "TablePayments", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).payments
    }
}
