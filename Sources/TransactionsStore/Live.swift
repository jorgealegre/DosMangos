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

    func fetchTransactions(date: Date) async throws -> [Transaction] {
        try container.viewContext.fetch(CDTransaction.fetchRequest()).map {
            Transaction(
                date: $0.createdAt,
                description: $0.name,
                id: $0.id,
                value: $0.value
            )
        }
    }

    func saveTransactions(_ transaction: Transaction) async {
        let cdTransaction = CDTransaction(entity: NSEntityDescription.entity(forEntityName: "Transaction", in: container.viewContext)!, insertInto: container.viewContext)

        cdTransaction.id = transaction.id
        cdTransaction.name = transaction.description
        cdTransaction.createdAt = transaction.date
        cdTransaction.value = transaction.value

        try! container.viewContext.save()
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
