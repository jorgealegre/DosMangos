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

        try db.createViews()
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
          "localDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "locationID" TEXT REFERENCES "transaction_locations"("id") ON DELETE SET NULL
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "transaction_locations" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "latitude" REAL NOT NULL,
          "longitude" REAL NOT NULL,
          "city" TEXT,
          "countryCode" TEXT
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "categories" (
          "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL,
          "parentCategoryID" TEXT REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE
        ) STRICT
        """
        )
        .execute(db)
        try #sql(
        """
        CREATE TABLE "transactionsCategories" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
          "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE,
          UNIQUE("transactionID", "categoryID") ON CONFLICT IGNORE
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
          "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE,
          UNIQUE("transactionID", "tagID") ON CONFLICT IGNORE
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

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_categories_parentCategoryID"
        ON "categories"("parentCategoryID")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactions_locationID"
        ON "transactions"("locationID")
        """
        )
        .execute(db)
    }

    migrator.registerMigration("Add currency conversion support") { db in
        // Add conversion columns as NULLABLE
        // NULL = conversion not yet available (offline, rate not found, etc.)
        try #sql(
        """
        ALTER TABLE "transactions"
        ADD COLUMN "convertedValueMinorUnits" INTEGER
        """
        )
        .execute(db)

        try #sql(
        """
        ALTER TABLE "transactions"
        ADD COLUMN "convertedCurrencyCode" TEXT
        """
        )
        .execute(db)

        // Create exchange_rates table for caching
        try #sql(
        """
        CREATE TABLE "exchangeRates" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "fromCurrency" TEXT NOT NULL,
          "toCurrency" TEXT NOT NULL,
          "rate" REAL NOT NULL,
          "date" TEXT NOT NULL,
          "fetchedAt" TEXT NOT NULL DEFAULT (datetime('now')),
          UNIQUE("fromCurrency", "toCurrency", "date") ON CONFLICT REPLACE
        ) STRICT
        """
        )
        .execute(db)

        // Index for fast rate lookups
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_exchangeRates_lookup"
        ON "exchangeRates"("fromCurrency", "toCurrency", "date")
        """
        )
        .execute(db)

        // Backfill existing USD transactions (same currency, no conversion needed)
        try #sql(
        """
        UPDATE "transactions"
        SET "convertedValueMinorUnits" = "valueMinorUnits",
            "convertedCurrencyCode" = "currencyCode"
        WHERE "currencyCode" = 'USD'
        """
        )
        .execute(db)

        // Non-USD transactions remain NULL (we don't know historical rates)
    }

    try migrator.migrate(database)

    try database.write { db in
        // TODO: triggers
    }

    return database
}

// MARK: - Views

extension Database {
    func createViews() throws {

        try #sql("""
        CREATE TEMPORARY VIEW \(raw: TransactionCategoriesWithDisplayName.tableName) AS
        SELECT
            \(TransactionCategory.columns),
            CASE
                WHEN "category".\(raw: Category.columns.title.name) IS NULL THEN ''
                WHEN "parentCategory".\(raw: Category.columns.title.name) IS NOT NULL
                THEN "parentCategory".\(raw: Category.columns.title.name) || ' › ' || "category".\(raw: Category.columns.title.name)
                ELSE "category".\(raw: Category.columns.title.name)
            END AS \(raw: TransactionCategoriesWithDisplayName.columns.displayName.name)
        FROM \(raw: TransactionCategory.tableName)
        LEFT JOIN \(raw: Category.tableName) AS "category"
        ON \(TransactionCategory.columns.categoryID) = "category".\(raw: Category.columns.title.name)
        LEFT JOIN \(raw: Category.tableName) AS "parentCategory"
        ON "category".\(raw: Category.columns.parentCategoryID.name) = "parentCategory".\(raw: Category.columns.title.name)
        """)
        .execute(self)

        try TransactionsListRow.createTemporaryView(
            as: Transaction
                .group(by: \.id)
                .leftJoin(TransactionCategoriesWithDisplayName.all) { $0.id.eq($1.transactionID) }
                .leftJoin(TransactionLocation.all) { $0.locationID.eq($2.id) }
                .withTags
                .select {
                    TransactionsListRow.Columns(
                        transaction: $0,
                        category: $1.displayName,
                        tags: $4.jsonTitles,
                        location: $2
                    )
                }

        )
        .execute(self)
    }
}

// TODO: db functions

nonisolated private let logger = Logger(subsystem: "DosMangos", category: "Database")

func seedSampleData() throws {
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid
    @Dependency(\.calendar) var calendar
    @Dependency(\.defaultDatabase) var database

    let nowLocal = now.localDateComponents()
    let thisMonthStart = Date.localDate(year: nowLocal.year, month: nowLocal.month, day: 1) ?? now
    let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart

    // Reference data
    let tagIDs = ["weekend", "friends", "guilty_pleasure", "work", "recurring", "health"]

    // Hierarchical categories
    let parentCategories = ["Home", "Food & Drinks"]
    let subcategories: [String: [String]] = [
        "Home": ["Furniture", "Maintenance", "Utilities"],
        "Food & Drinks": ["Restaurants", "Groceries"]
    ]
    let standaloneCategories = ["Entertainment", "Transport", "Salary", "Health"]

    // Build flat list for transaction assignment
    var categoryIDs: [String] = []
    categoryIDs.append(contentsOf: parentCategories)
    categoryIDs.append(contentsOf: standaloneCategories)
    for (_, subs) in subcategories {
        categoryIDs.append(contentsOf: subs)
    }

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

    // Create diverse locations
    let locations: [(latitude: Double, longitude: Double, city: String, countryCode: String)] = [
        (40.7128, -74.0060, "New York", "US"),
        (-34.6037, -58.3816, "Buenos Aires", "AR"),
        (51.5074, -0.1278, "London", "GB"),
        (35.6762, 139.6503, "Tokyo", "JP"),
        (-33.8688, 151.2093, "Sydney", "AU"),
        (48.8566, 2.3522, "Paris", "FR"),
        (19.0760, 72.8777, "Mumbai", "IN"),
    ]
    var locationIDs: [UUID] = []
    for _ in locations {
        locationIDs.append(uuid())
    }

    try database.write { db in
        try db.seed {
            for tagID in tagIDs {
                Tag(title: tagID)
            }

            // Create parent categories
            for parentID in parentCategories {
                Category(title: parentID, parentCategoryID: nil)
            }

            // Create subcategories
            for (parentID, subs) in subcategories {
                for subID in subs {
                    Category(title: subID, parentCategoryID: parentID)
                }
            }

            // Create standalone categories
            for categoryID in standaloneCategories {
                Category(title: categoryID, parentCategoryID: nil)
            }

            for (index, location) in locations.enumerated() {
                TransactionLocation(
                    id: locationIDs[index],
                    latitude: location.latitude,
                    longitude: location.longitude,
                    city: location.city,
                    countryCode: location.countryCode
                )
            }

            // Current month (~10)
            let currentMonthSeed: [(daysAgo: Int, hour: Int, description: String, valueMinorUnits: Int, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
                (0, 19, "Dinner at Alto El Fuego", 8050, .expense, 1, [0, 1]),
                (0, 9, "Coffee", 450, .expense, 1, [4]),
                (1, 18, "Groceries", 12490, .expense, 0, [4]),
                (2, 12, "Gym", 3999, .expense, 4, [5, 4]),
                (3, 8, "Taxi", 1890, .expense, 5, []),
                (5, 13, "Movie night", 1650, .expense, 2, [0]),
                (7, 10, "Lunch with friends", 2350, .expense, 1, [1]),
                (9, 16, "Salary", 250_000, .income, 6, [3, 4]),
                (12, 11, "Streaming subscription", 1299, .expense, 2, [4]),
                (15, 14, "Pharmacy", 2190, .expense, 4, [5]),
            ]

            for (index, seed) in currentMonthSeed.enumerated() {
                let id = uuid()
                let date = dateInSameMonthAsNow(daysAgo: seed.daysAgo, hourOffset: seed.hour + index % 2)
                let local = date.localDateComponents()
                let locationID = locationIDs[index % locationIDs.count]
                Transaction(
                    id: id,
                    description: seed.description,
                    valueMinorUnits: seed.valueMinorUnits,
                    currencyCode: "USD",
                    convertedValueMinorUnits: seed.valueMinorUnits,
                    convertedCurrencyCode: "USD",
                    type: seed.type,
                    createdAtUTC: date,
                    localYear: local.year,
                    localMonth: local.month,
                    localDay: local.day,
                    locationID: locationID
                )

                TransactionCategory.Draft(transactionID: id, categoryID: categoryIDs[seed.categoryIndex])
                for tagIndex in seed.tagIndices {
                    TransactionTag.Draft(transactionID: id, tagID: tagIDs[tagIndex])
                }
            }

            // Previous month (a few)
            let previousMonthSeed: [(dayOffset: Int, hour: Int, description: String, valueMinorUnits: Int, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
                (2, 9, "Book", 1899, .expense, 3, []),
                (6, 20, "Dinner out", 5400, .expense, 1, [0]),
                (14, 12, "Internet bill", 5999, .expense, 0, [4]),
                (21, 10, "Side project", 42000, .income, 6, [3]),
            ]

            for (index, seed) in previousMonthSeed.enumerated() {
                let id = uuid()
                let date = dateInPreviousMonth(dayOffsetFromStart: seed.dayOffset, hourOffset: seed.hour)
                let local = date.localDateComponents()
                let locationID = locationIDs[(index + 3) % locationIDs.count]
                Transaction(
                    id: id,
                    description: seed.description,
                    valueMinorUnits: seed.valueMinorUnits,
                    currencyCode: "USD",
                    convertedValueMinorUnits: seed.valueMinorUnits,
                    convertedCurrencyCode: "USD",
                    type: seed.type,
                    createdAtUTC: date,
                    localYear: local.year,
                    localMonth: local.month,
                    localDay: local.day,
                    locationID: locationID
                )

                TransactionCategory.Draft(transactionID: id, categoryID: categoryIDs[seed.categoryIndex])
                for tagIndex in seed.tagIndices {
                    TransactionTag.Draft(transactionID: id, tagID: tagIDs[tagIndex])
                }
            }
        }
    }
}
