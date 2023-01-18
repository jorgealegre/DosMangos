import Foundation
import CoreData

@objc(CDTransaction)
final class CDTransaction: NSManagedObject, Identifiable {
    static func fetchRequest() -> NSFetchRequest<CDTransaction> {
        NSFetchRequest<CDTransaction>(entityName: "Transaction")
    }

    @NSManaged var createdAt: Date
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var value: Int
}
