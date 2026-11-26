import Foundation
import FutariDomain

enum ScreenshotDemo {
    static let isEnabled: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--screenshot-demo")
        #else
        false
        #endif
    }()

    static var isFree: Bool { hasArgument("--screenshot-free") }
    static var isDark: Bool { hasArgument("--screenshot-dark") }
    static var member: Member { hasArgument("--screenshot-partner") ? .second : .first }
    static var day: Date? { isEnabled ? date(18) : nil }

    static func price(for option: ProProduct) -> String? {
        guard isEnabled, let value = ProcessInfo.processInfo.environment[option.rawValue],
              let yen = Int(value), yen > 0 else { return nil }
        return "\(yen.yen)（仮の値）"
    }

    static func expenses() throws -> [Expense] {
        [
            try Expense(amount: 8_420, date: date(17), category: .groceries, payer: .first,
                        split: .equal, label: "週末の買い出し"),
            try Expense(amount: 4_600, date: date(14), category: .dining, payer: .second,
                        split: .equal, label: "ふたりの夕食"),
            try Expense(amount: 2_400, date: date(9), category: .household, payer: .first,
                        split: .equal, label: "洗剤と消耗品")
        ]
    }

    private static func hasArgument(_ argument: String) -> Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(argument)
    }

    private static func date(_ day: Int) -> Date {
        Month.calendar.date(from: DateComponents(year: 2026, month: 6, day: day))!
    }
}
