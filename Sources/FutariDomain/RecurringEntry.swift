import CryptoKit
import Foundation

public enum RecurringEntry {
    public static func id(bookID: UUID, templateID: UUID, month: Month) -> UUID {
        let seconds = Int(month.start.timeIntervalSince1970)
        let identity = "\(bookID.uuidString)/\(templateID.uuidString)/\(seconds)"
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        // RFC 9562 custom UUID, with the standard variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func missing(
        bookID: UUID, templates: [Expense], month: Month, existingIDs: Set<UUID>, isSettled: Bool
    ) throws -> [Expense] {
        guard !isSettled else { return [] }
        var seen = existingIDs
        return try templates.compactMap { template in
            guard Month(containing: template.date).start <= month.start else { return nil }
            let id = id(bookID: bookID, templateID: template.id, month: month)
            guard seen.insert(id).inserted else { return nil }
            return try Expense(id: id, amount: template.amount, date: month.start,
                               category: template.category, payer: template.payer,
                               split: template.split, label: template.label)
        }
    }
}

public extension Ledger {
    static func budgetRemaining(limit: Int, spent: Int) -> Int { limit - spent }
}
