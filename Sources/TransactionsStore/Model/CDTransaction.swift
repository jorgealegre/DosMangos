import Foundation
import CoreData
import SharedModels

@objc(CDTransaction)
final class CDTransaction: NSManagedObject, Identifiable {
    @NSManaged var createdAt: Date
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var value: Int

    static func insert(into context: NSManagedObjectContext, transaction: Transaction) -> CDTransaction {
        let cdTransaction: CDTransaction = context.insertObject()
        cdTransaction.id = transaction.id
        cdTransaction.createdAt = transaction.date
        cdTransaction.name = transaction.description
        cdTransaction.value = transaction.value
        return cdTransaction
    }
}

extension CDTransaction: Managed {
    static var defaultSortDescriptors: [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDTransaction.createdAt, ascending: false)]
    }
}
