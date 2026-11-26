import Foundation

public struct MonthlySpending: Identifiable {
    public let month: Month
    public let amount: Int
    public var id: Month { month }
}

public enum ProInsights {
    public static func spending(_ expenses: [Expense], starting month: Month, count: Int) throws -> [MonthlySpending] {
        let end = month.advanced(by: count)
        var totals: [Month: Int] = [:]
        for expense in expenses where expense.date >= month.start && expense.date < end.start {
            let key = Month(containing: expense.date)
            totals[key] = try Ledger.sum(totals[key, default: 0], expense.amount)
        }
        return (0..<count).map { offset in
            let key = month.advanced(by: offset)
            return MonthlySpending(month: key, amount: totals[key, default: 0])
        }
    }

    public static func csv(_ rows: [[String]]) -> Data {
        let lines = rows.map { row in
            row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                .joined(separator: ",")
        }
        return Data(("\u{FEFF}" + lines.map { $0 + "\r\n" }.joined()).utf8)
    }

    public static func settlementDate(day: Int, in month: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day), let days = calendar.range(of: .day, in: .month, for: month) else {
            return nil
        }
        var parts = calendar.dateComponents([.year, .month], from: month)
        parts.day = min(day, days.count)
        parts.hour = 9
        return calendar.date(from: parts)
    }
}
