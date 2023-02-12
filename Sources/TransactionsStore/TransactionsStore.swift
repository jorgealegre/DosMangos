import Dependencies
import Foundation
import IdentifiedCollections
import SharedModels
import XCTestDynamicOverlay

public struct TransactionsStore {
    public var migrate: @Sendable () async throws -> Void

    public var deleteTransactions: @Sendable (_ ids: [UUID]) async throws -> Void
    public var fetchTransactions: @Sendable (_ date: Date) async throws -> IdentifiedArrayOf<Transaction>
    public var saveTransaction: @Sendable (Transaction) async throws -> Void

    public init(
        migrate: @Sendable @escaping () async -> Void,
        deleteTransactions: @Sendable @escaping (_: [UUID]) async -> Void,
        fetchTransactions: @Sendable @escaping (_: Date) async -> IdentifiedArrayOf<Transaction>,
        saveTransaction: @Sendable @escaping (Transaction) async -> Void
    ) {
        self.migrate = migrate
        self.deleteTransactions = deleteTransactions
        self.fetchTransactions = fetchTransactions
        self.saveTransaction = saveTransaction
    }
}

extension DependencyValues {
    public var transactionsStore: TransactionsStore {
        get { self[TransactionsStore.self] }
        set { self[TransactionsStore.self] = newValue }
    }
}

extension TransactionsStore: TestDependencyKey {
    public static let previewValue = Self.mock

    public static let testValue = Self(
        migrate: unimplemented("\(Self.self).migrate"),
        deleteTransactions: unimplemented("\(Self.self).deleteTransactions"),
        fetchTransactions: unimplemented("\(Self.self).fetchTransactions"),
        saveTransaction: unimplemented("\(Self.self).saveTransaction")
    )
}

extension TransactionsStore {
    public static var mock: Self {
        Self(
            migrate: {},
            deleteTransactions: { _ in },
            fetchTransactions: { _ in [.mock()] },
            saveTransaction: { _ in }
        )
    }
}
