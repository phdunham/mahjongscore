import XCTest
@testable import MahjongCore

final class TablePaymentsTests: XCTestCase {

    func test_loads_withUniqueIds() throws {
        let payments = try TablePayments.load()
        XCTAssertFalse(payments.isEmpty)
        XCTAssertEqual(Set(payments.map(\.id)).count, payments.count)
    }

    /// Every linked rule must exist, and every "other" (non-hand) rule in
    /// Rules.json must be covered — so the two files can't drift apart.
    func test_staysInStepWithRulesJSON() throws {
        let payments = try TablePayments.load()
        let rules = try RuleTable.load()
        let ruleIds = Set(rules.patterns.map(\.id))
        for p in payments {
            if let rid = p.ruleId {
                XCTAssertTrue(ruleIds.contains(rid), "\(p.id) links to unknown rule \(rid)")
            }
        }
        let covered = Set(payments.compactMap(\.ruleId))
        for rule in rules.patterns where rule.category == "other" {
            XCTAssertTrue(covered.contains(rule.id), "Rules.json '\(rule.id)' has no table-payment entry")
        }
    }

    func test_everyPaymentHasAnAmount() throws {
        for p in try TablePayments.load() {
            XCTAssertTrue((p.basesEach != nil) != (p.fixedTai != nil),
                          "\(p.id) needs exactly one of basesEach / fixedTai")
            XCTAssertGreaterThan(p.payments, 0)
        }
    }

    func test_amountsScaleWithBase() throws {
        let payments = try TablePayments.load()
        let dice = try XCTUnwrap(payments.first { $0.id == "dice-one-two-three" })
        XCTAssertEqual(dice.taiEach(base: 5), 5)
        XCTAssertEqual(dice.taiTotal(base: 5), 15)
        XCTAssertEqual(dice.taiTotal(base: 10), 30)

        let grass = try XCTUnwrap(payments.first { $0.id == "one-grass" })
        XCTAssertEqual(grass.taiEach(base: 5), 2.5)

        let falseWin = try XCTUnwrap(payments.first { $0.id == "false-win-penalty" })
        XCTAssertEqual(falseWin.taiEach(base: 5), 30)
        XCTAssertEqual(falseWin.taiEach(base: 10), 30, "flat penalty ignores the base")
    }
}
