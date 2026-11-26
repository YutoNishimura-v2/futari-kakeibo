import CoreData
import Foundation

@objc(LedgerBookRow)
final class LedgerBookRow: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var migrated: Bool
    @NSManaged var title: String?
}

@objc(LedgerExpenseRow)
final class LedgerExpenseRow: NSManagedObject {
    @NSManaged var book: LedgerBookRow?
    @NSManaged var payload: Data?
    @NSManaged var receiptJPEG: Data?
    @NSManaged var recurringID: UUID?
}

@objc(LedgerEditRow)
final class LedgerEditRow: NSManagedObject {
    @NSManaged var book: LedgerBookRow?
    @NSManaged var key: String?
    @NSManaged var value: String?
    @NSManaged var time: Date?
    @NSManaged var id: UUID?

    var order: EditOrder? {
        guard let time, let id else { return nil }
        return EditOrder(time: time, id: id)
    }
}

func ledgerModel() -> NSManagedObjectModel {
    func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let field = NSAttributeDescription()
        field.name = name
        field.attributeType = type
        field.isOptional = true
        return field
    }

    func entity(_ type: NSManagedObject.Type, _ fields: [NSAttributeDescription]) -> NSEntityDescription {
        let description = NSEntityDescription()
        description.name = NSStringFromClass(type)
        description.managedObjectClassName = NSStringFromClass(type)
        description.properties = fields
        return description
    }

    let migrated = attribute("migrated", .booleanAttributeType)
    migrated.isOptional = false
    migrated.defaultValue = false
    let book = entity(LedgerBookRow.self, [
        attribute("id", .UUIDAttributeType), migrated, attribute("title", .stringAttributeType)
    ])
    let receiptJPEG = attribute("receiptJPEG", .binaryDataAttributeType)
    receiptJPEG.allowsExternalBinaryDataStorage = true
    let expense = entity(LedgerExpenseRow.self, [
        attribute("payload", .binaryDataAttributeType), receiptJPEG, attribute("recurringID", .UUIDAttributeType)
    ])
    let edit = entity(LedgerEditRow.self, [
        attribute("id", .UUIDAttributeType), attribute("key", .stringAttributeType),
        attribute("value", .stringAttributeType), attribute("time", .dateAttributeType)
    ])

    // CloudKit shares the connected graph. A new child is linked and saved in the
    // book's store so Core Data exports it to the same share zone.
    func connect(_ child: NSEntityDescription, collection: String) {
        let parent = NSRelationshipDescription()
        parent.name = "book"
        parent.destinationEntity = book
        parent.maxCount = 1
        parent.isOptional = true
        parent.deleteRule = .nullifyDeleteRule
        let children = NSRelationshipDescription()
        children.name = collection
        children.destinationEntity = child
        children.maxCount = 0
        children.isOptional = true
        children.deleteRule = .cascadeDeleteRule
        parent.inverseRelationship = children
        children.inverseRelationship = parent
        child.properties += [parent]
        book.properties += [children]
    }

    connect(expense, collection: "expenses")
    connect(edit, collection: "edits")
    let model = NSManagedObjectModel()
    model.entities = [book, expense, edit]
    return model
}
