import Foundation
import FutariDomain
import SwiftData

@Model
final class StoredExpense {
    @Attribute(.unique) var id: UUID
    var amount: Int
    var date: Date
    var categoryKey: String
    var payerKey: String
    var splitKey: String
    var firstValue: Int
    var label: String?

    init(_ expense: Expense) {
        id = expense.id
        amount = expense.amount
        date = expense.date
        categoryKey = expense.category.rawValue
        payerKey = expense.payer.rawValue
        label = expense.label
        switch expense.split {
        case .equal:
            splitKey = "equal"
            firstValue = 0
        case let .ratio(first, _):
            splitKey = "ratio"
            firstValue = first
        case let .fixed(firstYen):
            splitKey = "fixed"
            firstValue = firstYen
        }
    }

    func expense() throws -> Expense {
        try ExpenseFields(id: id, amount: amount, date: date, categoryKey: categoryKey,
                          payerKey: payerKey, splitKey: splitKey, firstValue: firstValue,
                          label: label).expense()
    }
}

struct ExpenseFields: Codable {
    let id: UUID
    let amount: Int
    let date: Date
    let categoryKey: String
    let payerKey: String
    let splitKey: String
    let firstValue: Int
    let label: String?
    let customCategoryKey: String?

    init(id: UUID, amount: Int, date: Date, categoryKey: String, payerKey: String,
         splitKey: String, firstValue: Int, label: String?, customCategoryKey: String? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.categoryKey = categoryKey
        self.payerKey = payerKey
        self.splitKey = splitKey
        self.firstValue = firstValue
        self.label = label
        self.customCategoryKey = customCategoryKey
    }

    init(_ expense: Expense) {
        let splitKey: String
        let firstValue: Int
        switch expense.split {
        case .equal: (splitKey, firstValue) = ("equal", 0)
        case let .ratio(first, _): (splitKey, firstValue) = ("ratio", first)
        case let .fixed(firstYen): (splitKey, firstValue) = ("fixed", firstYen)
        }
        self.init(id: expense.id, amount: expense.amount, date: expense.date,
                  categoryKey: (expense.category.isCustom ? Category.other : expense.category).rawValue,
                  payerKey: expense.payer.rawValue, splitKey: splitKey, firstValue: firstValue,
                  label: expense.label, customCategoryKey: expense.category.isCustom ? expense.category.rawValue : nil)
    }

    func expense(registeredCategories: Set<Category>? = nil) throws -> Expense {
        guard let category = Category(rawValue: categoryKey),
              let payer = Member(rawValue: payerKey) else { throw ReadError.invalidEntry }
        let split: SplitRule
        switch splitKey {
        case "equal":
            split = .equal
        case "ratio":
            guard (0...100).contains(firstValue) else { throw ReadError.invalidEntry }
            split = .ratio(first: firstValue, second: 100 - firstValue)
        case "fixed":
            split = .fixed(firstYen: firstValue)
        default:
            throw ReadError.invalidEntry
        }
        let custom = customCategoryKey.flatMap(Category.init(rawValue:)).flatMap { candidate -> Category? in
            guard candidate.isCustom, registeredCategories?.contains(candidate) != false else { return nil }
            return candidate
        }
        return try Expense(id: id, amount: amount, date: date, category: custom ?? category,
                           payer: payer, split: split, label: label)
    }
}

@Model
final class SettledMonth {
    @Attribute(.unique) var start: Date

    init(_ month: Month) {
        start = month.start
    }
}

enum ReadError: Error {
    case invalidEntry
}

@MainActor
func readLegacyLedger() throws -> (expenses: [Expense], settled: Set<Month>, names: Names) {
    let schema = Schema([StoredExpense.self, SettledMonth.self])
    let local = ModelConfiguration(schema: schema, allowsSave: false, cloudKitDatabase: .none)
    let container: ModelContainer?
    if FileManager.default.fileExists(atPath: local.url.path) {
        container = try ModelContainer(for: schema, configurations: [local])
    } else {
        container = nil
    }
    let context = container?.mainContext
    let expenses = try context?.fetch(FetchDescriptor<StoredExpense>()).map { try $0.expense() } ?? []
    let markers = try context?.fetch(FetchDescriptor<SettledMonth>()) ?? []
    let defaults = UserDefaults.standard
    let names = Names(first: defaults.string(forKey: "firstName") ?? Names.firstDefault,
                      second: defaults.string(forKey: "secondName") ?? Names.secondDefault)
    return (expenses, Set(markers.map { Month(containing: $0.start) }), names)
}
