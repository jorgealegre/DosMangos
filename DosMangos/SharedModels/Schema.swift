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
        @Dependency(\.calendar) var calendar

        let nowLocal = now.localDateComponents()
        let thisMonthStart = Date.localDate(year: nowLocal.year, month: nowLocal.month, day: 1) ?? now
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart

        // Reference data
        let tagIDs = ["weekend", "friends", "guilty_pleasure", "work", "recurring", "health"]
        let categoryIDs = ["Home", "Food & Drinks", "Entertainment", "Personal", "Health", "Transport", "Salary"]

        // We want ~10 transactions in the current month and a few in the previous month.
        //
        // Some months (early in the month) won't have enough past days yet, so if a "days ago" value
        // would cross into the previous month we fall back to early-in-month days instead.
        func dateInSameMonthAsNow(daysAgo: Int, hourOffset: Int) -> Date {
            let candidate = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let candidateYM = calendar.dateComponents([.year, .month], from: candidate)
            if candidateYM.year == nowLocal.year, candidateYM.month == nowLocal.month {
                let base = calendar.startOfDay(for: candidate)
                return calendar.date(byAdding: .hour, value: hourOffset, to: base) ?? candidate
            } else {
                let fallback = calendar.date(byAdding: .day, value: min(daysAgo, 20), to: thisMonthStart) ?? thisMonthStart
                let base = calendar.startOfDay(for: fallback)
                return calendar.date(byAdding: .hour, value: hourOffset, to: base) ?? fallback
            }
        }

        func dateInPreviousMonth(dayOffsetFromStart: Int, hourOffset: Int) -> Date {
            let baseDay = calendar.date(byAdding: .day, value: dayOffsetFromStart, to: previousMonthStart) ?? previousMonthStart
            let base = calendar.startOfDay(for: baseDay)
            return calendar.date(byAdding: .hour, value: hourOffset, to: base) ?? baseDay
        }

        try seed {
            for tagID in tagIDs {
              Tag(title: tagID)
            }

            for categoryID in categoryIDs {
              Category(title: categoryID)
            }

            // Current month (~10)
            let currentMonthSeed: [(daysAgo: Int, hour: Int, description: String, valueMinorUnits: Int, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
                (0, 19, "Dinner at Alto El Fuego", -8050, .expense, 1, [0, 1]),
                (0, 9, "Coffee", -450, .expense, 1, [4]),
                (1, 18, "Groceries", -12490, .expense, 0, [4]),
                (2, 12, "Gym", -3999, .expense, 4, [5, 4]),
                (3, 8, "Taxi", -1890, .expense, 5, []),
                (5, 13, "Movie night", -1650, .expense, 2, [0]),
                (7, 10, "Lunch with friends", -2350, .expense, 1, [1]),
                (9, 16, "Salary", 250_000, .income, 6, [3, 4]),
                (12, 11, "Streaming subscription", -1299, .expense, 2, [4]),
                (15, 14, "Pharmacy", -2190, .expense, 4, [5]),
            ]

            for (index, seed) in currentMonthSeed.enumerated() {
                let id = uuid()
                let date = dateInSameMonthAsNow(daysAgo: seed.daysAgo, hourOffset: seed.hour + index % 2)
                let local = date.localDateComponents()
                Transaction(
                    id: id,
                    description: seed.description,
                    valueMinorUnits: seed.valueMinorUnits,
                    currencyCode: "USD",
                    type: seed.type,
                    createdAtUTC: date,
                    localYear: local.year,
                    localMonth: local.month,
                    localDay: local.day
                )

                TransactionCategory.Draft(transactionID: id, categoryID: categoryIDs[seed.categoryIndex])
                for tagIndex in seed.tagIndices {
                    TransactionTag.Draft(transactionID: id, tagID: tagIDs[tagIndex])
                }
            }

            // Previous month (a few)
            let previousMonthSeed: [(dayOffset: Int, hour: Int, description: String, valueMinorUnits: Int, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
                (2, 9, "Book", -1899, .expense, 3, []),
                (6, 20, "Dinner out", -5400, .expense, 1, [0]),
                (14, 12, "Internet bill", -5999, .expense, 0, [4]),
                (21, 10, "Side project", 42000, .income, 6, [3]),
            ]

            for seed in previousMonthSeed {
                let id = uuid()
                let date = dateInPreviousMonth(dayOffsetFromStart: seed.dayOffset, hourOffset: seed.hour)
                let local = date.localDateComponents()
                Transaction(
                    id: id,
                    description: seed.description,
                    valueMinorUnits: seed.valueMinorUnits,
                    currencyCode: "USD",
                    type: seed.type,
                    createdAtUTC: date,
                    localYear: local.year,
                    localMonth: local.month,
                    localDay: local.day
                )

                TransactionCategory.Draft(transactionID: id, categoryID: categoryIDs[seed.categoryIndex])
                for tagIndex in seed.tagIndices {
                    TransactionTag.Draft(transactionID: id, tagID: tagIDs[tagIndex])
                }
            }
        }
    }
}
#endif
