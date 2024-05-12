import Dependencies
import DependenciesMacros
import Foundation
import IdentifiedCollections
import SharedModels

@DependencyClient
public struct TransactionsStore: TestDependencyKey {
    public var migrate: @Sendable () async throws -> Void

    public var deleteTransactions: @Sendable (_ ids: [UUID]) async throws -> Void
    public var fetchTransactions: @Sendable (_ date: Date) async throws -> IdentifiedArrayOf<Transaction>
    public var saveTransaction: @Sendable (Transaction) async throws -> Void

    public static let previewValue = Self(
        migrate: {},
        deleteTransactions: { _ in },
        fetchTransactions: { _ in [.mock()] },
        saveTransaction: { _ in }
    )

    public static let testValue = Self()
}

extension DependencyValues {
    public var transactionsStore: TransactionsStore {
        get { self[TransactionsStore.self] }
        set { self[TransactionsStore.self] = newValue }
    }
}
