import Foundation

public enum Member: String, CaseIterable {
    case first, second

    public var other: Member { self == .first ? .second : .first }
}

public struct Category: RawRepresentable, Hashable, CaseIterable {
    public static let groceries = Category(name: "groceries")
    public static let dining = Category(name: "dining")
    public static let household = Category(name: "household")
    public static let housing = Category(name: "housing")
    public static let utilities = Category(name: "utilities")
    public static let transport = Category(name: "transport")
    public static let leisure = Category(name: "leisure")
    public static let other = Category(name: "other")
    public static let allCases = [groceries, dining, household, housing, utilities, transport, leisure, other]

    public let rawValue: String
    public var isCustom: Bool { rawValue.hasPrefix("custom-") }

    private init(name: String) { rawValue = name }

    public init(customID: UUID) {
        rawValue = "custom-\(customID.uuidString)"
    }

    public init?(rawValue: String) {
        if let standard = Self.allCases.first(where: { $0.rawValue == rawValue }) {
            self = standard
        } else if rawValue.hasPrefix("custom-"), let id = UUID(uuidString: String(rawValue.dropFirst(7))) {
            self = Category(customID: id)
        } else {
            return nil
        }
    }
}

public enum LedgerError: Error {
    case invalidAmount, invalidRatio, invalidFixedAmount, labelTooLong, totalTooLarge
}

public enum SplitRule: Equatable {
    case equal
    case ratio(first: Int, second: Int)
    case fixed(firstYen: Int)

    public func firstShare(of amount: Int, paidBy payer: Member) throws -> Int {
        guard amount != 0, (-Ledger.maximumYen...Ledger.maximumYen).contains(amount)
        else { throw LedgerError.invalidAmount }
        let magnitude = abs(amount)
        let firstPercent: Int
        switch self {
        case .equal:
            firstPercent = 50
        case let .ratio(first, second):
            guard (0...100).contains(first), second == 100 - first else {
                throw LedgerError.invalidRatio
            }
            firstPercent = first
        case let .fixed(firstYen):
            guard (0...magnitude).contains(firstYen) else { throw LedgerError.invalidFixedAmount }
            return amount < 0 ? -firstYen : firstYen
        }
        // The payer absorbs a fractional yen on expenses and refunds alike.
        let otherPercent = payer == .first ? 100 - firstPercent : firstPercent
        let otherShare = magnitude / 100 * otherPercent + (magnitude % 100) * otherPercent / 100
        let share = payer == .first ? magnitude - otherShare : otherShare
        return amount < 0 ? -share : share
    }
}

public struct Expense: Identifiable {
    public let id: UUID
    public let amount: Int
    public let date: Date
    public let category: Category
    public let payer: Member
    public let split: SplitRule
    public let label: String?
    public let firstShare: Int

    public var hasSplitRemainder: Bool {
        switch split {
        case .equal: return amount % 2 != 0
        case let .ratio(first, _): return (amount % 100) * first % 100 != 0
        case .fixed: return false
        }
    }

    public init(
        id: UUID = UUID(), amount: Int, date: Date, category: Category,
        payer: Member, split: SplitRule, label: String? = nil
    ) throws {
        self.firstShare = try split.firstShare(of: amount, paidBy: payer)
        let cleaned = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard cleaned.count <= 30 else { throw LedgerError.labelTooLong }
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.payer = payer
        self.split = split
        self.label = cleaned.isEmpty ? nil : cleaned
    }
}

public struct Month: Hashable {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    public let start: Date

    public init(containing date: Date) {
        start = Self.calendar.dateInterval(of: .month, for: date)!.start
    }

    public var dates: Range<Date> { start..<advanced(by: 1).start }

    public func advanced(by months: Int) -> Month {
        Month(containing: Self.calendar.date(byAdding: .month, value: months, to: start)!)
    }

    // The ledger uses Japan's day. Store it as a UTC day label to preserve existing month keys.
    public static func localDay(_ date: Date) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar.date(from: local.dateComponents([.year, .month, .day], from: date))!
    }
}

public struct Settlement: Equatable {
    public let from: Member
    public let to: Member
    public let amount: Int
}

public struct BudgetProgress {
    public let limit: Int
    public let remaining: Int
    public let overspend: Int
    public let percentageUsed: Double?
    public let progress: Double
    public let displayPercentage: Double?
}

public enum Ledger {
    public static func budgetProgress(limit: Int, spent: Int) -> BudgetProgress {
        let balance = budgetRemaining(limit: limit, spent: spent)
        let overspend = max(0, -balance)
        let used = Double(max(0, spent))
        let percentageUsed: Double? = limit > 0 ? 100 * used / Double(limit) : (used == 0 ? 0 : nil)
        let progress = min(1, (percentageUsed ?? 100) / 100)
        let displayPercentage = overspend > 0 && limit > 0
            ? -(100 * Double(overspend) / Double(limit)).rounded(.up)
            : percentageUsed?.rounded(.down)
        return BudgetProgress(limit: limit, remaining: max(0, balance), overspend: overspend,
                              percentageUsed: percentageUsed, progress: progress,
                              displayPercentage: displayPercentage)
    }

    public static func budgetTotal(limits: [Category: Int], totals: [Category: Int]) throws -> BudgetProgress {
        let limit = try limits.values.reduce(0, sum)
        let spent = try limits.keys.reduce(0) { try sum($0, totals[$1, default: 0]) }
        return budgetProgress(limit: limit, spent: spent)
    }

    // Keep integer yen exactly representable in the Node mirror.
    public static let maximumYen = 9_007_199_254_740_991

    public static func settlement(
        for expenses: [Expense], in dates: Range<Date>, settledMonths: Set<Month> = []
    ) throws -> Settlement? {
        var firstOwes = 0
        var secondOwes = 0
        for expense in expenses where dates.contains(expense.date) {
            guard !settledMonths.contains(Month(containing: expense.date)) else { continue }
            if expense.payer == .first {
                secondOwes = try sum(secondOwes, expense.amount - expense.firstShare)
            } else {
                firstOwes = try sum(firstOwes, expense.firstShare)
            }
        }
        let net = try sum(firstOwes, -secondOwes)
        guard net != 0 else { return nil }
        let from: Member = net > 0 ? .first : .second
        return Settlement(from: from, to: from.other, amount: abs(net))
    }

    public static func spendingTotal(for expenses: [Expense], in month: Month) throws -> Int {
        let dates = month.dates
        var total = 0
        for expense in expenses where dates.contains(expense.date) {
            total = try sum(total, expense.amount)
        }
        return total
    }

    public static func totals(for expenses: [Expense], in month: Month) throws -> [Category: Int] {
        let dates = month.dates
        var totals: [Category: Int] = [:]
        for expense in expenses where dates.contains(expense.date) {
            totals[expense.category] = try sum(totals[expense.category, default: 0], expense.amount)
        }
        return totals
    }

    static func sum(_ left: Int, _ right: Int) throws -> Int {
        let total = left + right
        guard (-maximumYen...maximumYen).contains(total) else { throw LedgerError.totalTooLarge }
        return total
    }
}
