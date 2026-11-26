import Foundation
import FutariDomain
import WidgetKit

@MainActor
enum WidgetPublishing {
    static func publish(access: ProAccess, snapshot: LedgerSnapshot?, bookTitle: String?) {
        guard let defaults = LedgerWidgetData.defaults else { return }
        var next: Data?
        if access.plan.allowsProFeatures, let snapshot, let member = snapshot.member, let bookTitle {
            let month = Month(containing: Month.localDay(.now))
            let data = LedgerWidgetData(
                month: month, book: bookTitle,
                budgetRemaining: try? remaining(in: month, snapshot: snapshot),
                amountOwed: try? owed(by: member, in: month, snapshot: snapshot),
                proExpiresAt: access.expiresAt
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            next = try? encoder.encode(data)
        }
        guard defaults.data(forKey: LedgerWidgetData.key) != next else { return }
        if let next {
            defaults.set(next, forKey: LedgerWidgetData.key)
        } else {
            defaults.removeObject(forKey: LedgerWidgetData.key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: LedgerWidgetData.kind)
    }

    private static func remaining(in month: Month, snapshot: LedgerSnapshot) throws -> Int? {
        guard let budgets = snapshot.budgets[month], !budgets.isEmpty else { return nil }
        let totals = try Ledger.totals(for: snapshot.expenses, in: month)
        var remaining = 0
        for (category, limit) in budgets {
            let balance = Ledger.budgetRemaining(limit: limit, spent: totals[category, default: 0])
            let (sum, overflow) = remaining.addingReportingOverflow(balance)
            guard !overflow else { throw LedgerError.totalTooLarge }
            remaining = sum
        }
        return remaining
    }

    private static func owed(by member: Member, in month: Month, snapshot: LedgerSnapshot) throws -> Int {
        let payment = try Ledger.settlement(for: snapshot.expenses, in: month.dates, settledMonths: snapshot.settled)
        guard let payment, payment.from == member else { return 0 }
        return payment.amount
    }
}
