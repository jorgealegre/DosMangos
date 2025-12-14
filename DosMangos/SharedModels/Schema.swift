import Dependencies
import OSLog
import SQLiteData

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        defaultDatabase = try appDatabase()
    }
}

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
#if DEBUG
        db.trace(options: .profile) {
            if context == .live {
                logger.debug("\($0.expandedDescription)")
            } else {
                print("\($0.expandedDescription)")
            }
        }
#endif
    }
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    logger.debug(
    """
    App database:
    open "\(database.path)"
    """
    )
    var migrator = DatabaseMigrator()
#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
#endif
    migrator.registerMigration("Create initial tables") { db in
//        let defaultListColor = Color.HexRepresentation(queryOutput: RemindersList.defaultColor).hexValue
        try #sql(
        """
        CREATE TABLE "transactions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "description" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "valueMinorUnits" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "currencyCode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "type" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
          "localYear" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "localMonth" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "localDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "categories" (
          "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "transactionsCategories" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
          "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "tags" (
          "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "transactionsTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
        ) STRICT
        """
        )
        .execute(db)
    }

    migrator.registerMigration("Create foreign key indexes") { db in
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactions_localYMD_createdAtUTC"
        ON "transactions"("localYear", "localMonth", "localDay", "createdAtUTC")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_transactionID"
        ON "transactionsCategories"("transactionID")
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_categoryID"
        ON "transactionsCategories"("categoryID")
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactionsTags_transactionID"
        ON "transactionsTags"("transactionID")
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactionsTags_tagID"
        ON "transactionsTags"("tagID")
        """
        )
        .execute(db)
    }

    try migrator.migrate(database)

    try database.write { db in
        // TODO: triggers

        if context != .live {
            try db.seedSampleData()
        }
    }

    return database
}

// TODO: db functions

nonisolated private let logger = Logger(subsystem: "DosMangos", category: "Database")

#if DEBUG
extension Database {
    func seedSampleData() throws {
        @Dependency(\.date.now) var now
        @Dependency(\.uuid) var uuid

        let transactionIDs = (0...10).map { _ in uuid() }
        let local = now.localDateComponents()
        try seed {
            Transaction(
                id: transactionIDs[0],
                description: "Dinner at Alto El Fuego",
                valueMinorUnits: 100500_00,
                currencyCode: "ARS",
                type: .expense,
                createdAtUTC: now,
                localYear: local.year,
                localMonth: local.month,
                localDay: local.day
            )

            let tagIDs = ["weekend", "friends", "guilty_pleasure"]
            for tagID in tagIDs {
              Tag(title: tagID)
            }

            let categoryIDs = ["Home", "Food & Drinks", "Entertainment", "Personal", "Health"]
            for categoryID in categoryIDs {
              Category(title: categoryID)
            }

            TransactionTag.Draft(transactionID: transactionIDs[0], tagID: tagIDs[0])

            TransactionCategory.Draft(transactionID: transactionIDs[0], categoryID: categoryIDs[1])
        }
    }
}
#endif
