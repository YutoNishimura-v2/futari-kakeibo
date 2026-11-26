import Foundation

public struct LedgerWidgetData: Codable {
    public static let kind = "LedgerSummary"
    public static let key = "ledger.widgetSummary"

    public static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LedgerAppGroup") as? String else { return nil }
        return UserDefaults(suiteName: group)
    }

    public let monthStart: Date
    public let book: String
    public let budgetRemaining: Int?
    public let amountOwed: Int?
    public let proExpiresAt: Date?

    public init(month: Month, book: String, budgetRemaining: Int?, amountOwed: Int?, proExpiresAt: Date?) {
        monthStart = month.start
        self.book = book
        self.budgetRemaining = budgetRemaining
        self.amountOwed = amountOwed
        self.proExpiresAt = proExpiresAt
    }

    public func isCurrent(at date: Date) -> Bool {
        monthStart == Month(containing: Month.localDay(date)).start
    }
}
