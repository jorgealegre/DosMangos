import CoreData
import Dependencies
import Foundation
import SharedModels

private class CoreData {

    let container: NSPersistentContainer

    init() {
        let bundle = Bundle.module
        let modelURL = bundle.url(forResource: "Model", withExtension: ".momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!
        container = NSPersistentContainer(name: "Model", managedObjectModel: model)
    }

    func loadPersistentStore() async {
        await withUnsafeContinuation { continuation in
            container.loadPersistentStores { description, error in
                print(description)
                if let error = error {
                    fatalError("Unable to load persistent stores: \(error)")
                }
                continuation.resume()
            }
        }
    }

    func deleteTransactions(_ ids: [UUID]) async throws {
        let fetchRequest = CDTransaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        let result = try container.viewContext.execute(deleteRequest) as? NSBatchDeleteResult

        guard let deleteResult = result?.result as? [NSManagedObjectID] else { return }

        let deletedObjects: [AnyHashable: Any] = [
            NSDeletedObjectsKey: deleteResult
        ]

        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: deletedObjects,
            into: [container.viewContext]
        )
    }

    func fetchTransactions(date: Date) async throws -> [Transaction] {
        // TODO: filter by month from date
        try container.viewContext
            .fetch(CDTransaction.sortedFetchRequest)
            .map {
                Transaction(
                    date: $0.createdAt,
                    description: $0.name,
                    id: $0.id,
                    value: $0.value
                )
            }
    }

    func saveTransactions(_ transaction: Transaction) async {
        container.viewContext.performChanges {
            let _ = CDTransaction.insert(into: self.container.viewContext, transaction: transaction)
        }
    }
}

extension TransactionsStore: DependencyKey {
    public static let liveValue: TransactionsStore = {
        let model = CoreData()

        return Self(
            migrate: {
                // TODO: error handling
                await model.loadPersistentStore()
            },
            deleteTransactions: { ids in
                // TODO: error handling
                return try! await model.deleteTransactions(ids)
            },
            fetchTransactions: { date in
                // TODO: error handling
                return try! await model.fetchTransactions(date: date)
            },
            saveTransaction: { transaction in
                await model.saveTransactions(transaction)
            }
        )
    }()
}

extension NSManagedObjectContext {

    func insertObject<A: NSManagedObject>() -> A where A: Managed {
        guard let obj = NSEntityDescription.insertNewObject(forEntityName: A.entityName, into: self) as? A else { fatalError("Wrong object type")
        }
        return obj
    }

    func saveOrRollback() -> Bool {
        do {
            try save()
            return true
        } catch {
            rollback()
            return false
        }
    }

    func performChanges(block: @escaping () -> ()) {
        perform {
            block()
            _ = self.saveOrRollback()
        }
    }
}
