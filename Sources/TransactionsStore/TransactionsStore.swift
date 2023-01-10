import ComposableArchitecture
import Dependencies
import Foundation
import SharedModels
import Sqlite
import XCTestDynamicOverlay

public struct TransactionsStore {
    public var fetchTransactions: @Sendable (_ date: Date) async throws -> [Transaction]
    public var migrate: @Sendable () async throws -> Void

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
        fetchTransactions: unimplemented("\(Self.self).fetchTransactions"),
        migrate: unimplemented("\(Self.self).migrate")
    )
}

extension TransactionsStore {
    public static var mock: Self {
        Self(
            fetchTransactions: { _ in [.mock] },
            migrate: {}
        )
    }
}

extension TransactionsStore {
    public static func live(path: URL) -> Self {
        let _db = UncheckedSendable(Box<Sqlite?>(wrappedValue: nil))
        @Sendable func db() throws -> Sqlite {
            if _db.value.wrappedValue == nil {
                try! FileManager.default.createDirectory(
                    at: path.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                _db.value.wrappedValue = try Sqlite(path: path.absoluteString)
            }
            return _db.value.wrappedValue!
        }
        return Self(
            fetchTransactions: { try db().fetchTransactions(for: $0) },
            migrate: { try db().migrate() }
        )
    }

    public static func autoMigratingLive(path: URL) -> Self {
        let client = Self.live(path: path)
        Task { try await client.migrate() }
        return client
    }
}

private let jsonEncoder = JSONEncoder()
private let jsonDecoder = JSONDecoder()

final class Box<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension Sqlite {
    func fetchTransactions(for date: Date) throws -> [Transaction] {
        return try self.run(
        """
        SELECT
            "id", "createdAt", "description", "value"
        FROM
            "transaction"
        ORDER BY "createdAt"
        """
        )
        .compactMap { row -> Transaction? in
            guard
                let createdAt = (/Sqlite.Datatype.real).extract(from: row[1]).map(Date.init(timeIntervalSince1970:)),
                let description = (/Sqlite.Datatype.text).extract(from: row[2]),
                let idString = (/Sqlite.Datatype.text).extract(from: row[0]),
                let id = idString.map(UUID.init(uuidString:)),
                let value = (/Sqlite.Datatype.real).extract(from: row[3])
            else { return nil }

            return Transaction(
                date: createdAt,
                description: description,
                id: id,
                value: Int(value)
            )
        }
    }

    func migrate() throws {
        try self.execute(
        """
        CREATE TABLE IF NOT EXISTS "transaction" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
            "createdAt" TIMESTAMP NOT NULL,
            "description" TEXT NOT NULL,
            "value" REAL NOT NULL
        );
        """
        )
    }
}

