import Foundation
import CoreData
import SharedModels

@objc(CDTransaction)
final class CDTransaction: NSManagedObject, Identifiable {
    @NSManaged var createdAt: Date
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var value: Int
    @NSManaged var transactionType: Int16

    static func insert(into context: NSManagedObjectContext, transaction: Transaction) -> CDTransaction {
        let cdTransaction: CDTransaction = context.insertObject()
        cdTransaction.id = transaction.id
        cdTransaction.createdAt = transaction.createdAt
        cdTransaction.name = transaction.description
        cdTransaction.value = transaction.absoluteValue
        cdTransaction.transactionType = Int16(transaction.transactionType.rawValue)
        return cdTransaction
    }
}

extension CDTransaction: Managed {
    static var defaultSortDescriptors: [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDTransaction.createdAt, ascending: false)]
    }
}
