import ComposableArchitecture
import Dependencies
import Foundation
import SharedModels
import Sqlite
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
            migrate: { try db().migrate() },
            fetchTransactions: { try db().fetchTransactions(for: $0) },
            saveTransaction: { try db().saveTransaction($0) }
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
            "transactions"
        ORDER BY "createdAt"
        """
        )
        .compactMap { row -> Transaction? in
            guard
                let createdAt = (/Sqlite.Datatype.integer).extract(from: row[1]),
                let description = (/Sqlite.Datatype.text).extract(from: row[2]),
                let idString = (/Sqlite.Datatype.text).extract(from: row[0]),
                let id = UUID.init(uuidString: idString),
                let value = (/Sqlite.Datatype.real).extract(from: row[3])
            else {
                // TODO: throw error instead
                return nil
            }

            return Transaction(
                date: Date(timeIntervalSince1970: Double(createdAt)),
                description: description,
                id: id,
                value: Int(value)
            )
        }
    }

    func saveTransaction(_ transaction: Transaction) throws {
        try self.run(
            """
            INSERT INTO "transactions" (
                "id", "createdAt", "description", "value"
            )
            VALUES (
                ?, ?, ?, ?
            );
            """,
            .text(transaction.id.uuidString),
            .integer(Int32(transaction.date.timeIntervalSince1970)),
            .text(transaction.description),
            .real(Double(transaction.value))
        )
    }

    func migrate() throws {
        try self.execute(
        """
        CREATE TABLE IF NOT EXISTS "transactions" (
            "id" STRING PRIMARY KEY NOT NULL UNIQUE,
            "createdAt" TIMESTAMP NOT NULL,
            "description" TEXT NOT NULL,
            "value" REAL NOT NULL
        );
        """
        )
    }
}

// INSERT INTO transactions (id, createdAt, description, value)
// VALUES ("DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF", 1673316697, "Description", 12.3);
