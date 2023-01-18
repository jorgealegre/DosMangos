import Dependencies
import Foundation
import SharedModels
import XCTestDynamicOverlay

public struct TransactionsStore {
    public var migrate: @Sendable () async throws -> Void

    public var fetchTransactions: @Sendable (_ date: Date) async throws -> [Transaction]
    public var saveTransaction: @Sendable (Transaction) async throws -> Void
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
        fetchTransactions: unimplemented("\(Self.self).fetchTransactions"),
        saveTransaction: unimplemented("\(Self.self).saveTransaction")
    )
}

extension TransactionsStore {
    public static var mock: Self {
        Self(
            migrate: {},
            fetchTransactions: { _ in [.mock] },
            saveTransaction: { _ in }
        )
    }
}
