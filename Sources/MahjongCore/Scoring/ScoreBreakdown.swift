import Foundation

/// A single tai award — a matched rule with a per-occurrence tai value and a count.
/// Multiple awards of the same rule are coalesced into one with count > 1
/// (e.g. two correct flowers = one award with count=2, totalTai = 2*2 = 4).
public struct TaiAward: Hashable, Codable, Sendable {
    public let ruleId: String
    public let nameZh: String
    public let nameEn: String
    public let taiPerCount: Int
    public let count: Int

    public init(ruleId: String, nameZh: String, nameEn: String, taiPerCount: Int, count: Int = 1) {
        self.ruleId = ruleId
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.taiPerCount = taiPerCount
        self.count = count
    }

    public var totalTai: Int { taiPerCount * count }
}

/// Full score breakdown for a winning hand.
public struct ScoreBreakdown: Hashable, Codable, Sendable {
    public let awards: [TaiAward]

    public init(awards: [TaiAward]) { self.awards = awards }

    public var totalTai: Int { awards.reduce(0) { $0 + $1.totalTai } }
}

// MARK: - Internal helpers for matchers

extension RuleTable {
    /// Create a TaiAward from a rule id, using this table for tai/names.
    func award(_ id: String, count: Int = 1) -> TaiAward {
        let r = rule(id: id)
        return TaiAward(
            ruleId: r.id,
            nameZh: r.nameZh,
            nameEn: r.nameEn,
            taiPerCount: r.tai,
            count: count
        )
    }
}
