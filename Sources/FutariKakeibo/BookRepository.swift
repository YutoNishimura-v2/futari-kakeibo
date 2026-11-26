import Foundation
import FutariDomain

struct Names: Equatable {
    static let firstDefault = "わたし"
    static let secondDefault = "パートナー"
    var first = Self.firstDefault
    var second = Self.secondDefault

    subscript(_ member: Member) -> String { member == .first ? first : second }
}

struct Book: Identifiable, Hashable {
    let id: UUID
    let isGuest: Bool
}

struct LedgerSnapshot: Identifiable {
    let book: Book
    var id: UUID { book.id }
    let revision = UUID()
    let member: Member?
    let names: Names
    let expenses: [Expense]
    let settlementDates: [Month: Date]
    var settled: Set<Month> { Set(settlementDates.keys) }
    let budgets: [Month: [Category: Int]]
    let recurring: [Expense]
    let customCategories: [Category: String]
    let shopping: [ShoppingItem]

    var categories: [Category] {
        Category.allCases + customCategories.keys.sorted { $0.rawValue < $1.rawValue }
    }

    func title(for category: Category) -> String { customCategories[category] ?? category.title }
}

@MainActor
protocol BookRepository {
    var snapshot: LedgerSnapshot? { get }
    func add(_ expense: Expense, to book: Book) throws
    func addTemplate(_ template: Expense, to book: Book) throws
    func setSettled(_ settled: Bool, month: Month, in book: Book) throws
    func rename(_ names: Names, replacing previous: Names, in book: Book) throws
}

enum BookError: Error {
    case unavailable, settled, otherPartner, unresolvedPartner, missingLink, proRequired
}

extension Member {
    static func forParticipant(isOwner: Bool, isPrivatePartner: Bool) -> Self? {
        if isOwner { return .first }
        return isPrivatePartner ? .second : nil
    }
}

struct EditOrder: Comparable {
    let time: Date
    let id: UUID

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.time != rhs.time { return lhs.time < rhs.time }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
