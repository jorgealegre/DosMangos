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

        // Create exchangeRates table for caching
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

    migrator.registerMigration("Add recurring transactions support") { db in
        // Create recurringTransactions table
        try #sql(
        """
        CREATE TABLE "recurringTransactions" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "description" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
          "valueMinorUnits" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "currencyCode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'USD',
          "type" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,

          -- Recurrence Rule (flattened)
          "frequency" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "interval" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
          "weeklyDays" TEXT,
          "monthlyMode" INTEGER,
          "monthlyDays" TEXT,
          "monthlyOrdinal" INTEGER,
          "monthlyWeekday" INTEGER,
          "yearlyMonths" TEXT,
          "yearlyDaysOfWeekEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "yearlyOrdinal" INTEGER,
          "yearlyWeekday" INTEGER,
          "endMode" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "endDate" TEXT,
          "endAfterOccurrences" INTEGER,

          -- State
          "startDate" TEXT NOT NULL DEFAULT (date('now')),
          "nextDueDate" TEXT NOT NULL DEFAULT (date('now')),
          "postedCount" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "status" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,

          -- Metadata
          "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
          "updatedAtUTC" TEXT NOT NULL DEFAULT (datetime('now'))
        ) STRICT
        """
        )
        .execute(db)

        // Create recurringTransactionsCategories join table
        try #sql(
        """
        CREATE TABLE "recurringTransactionsCategories" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
          "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE,
          UNIQUE("recurringTransactionID", "categoryID") ON CONFLICT IGNORE
        ) STRICT
        """
        )
        .execute(db)

        // Create recurringTransactionsTags join table
        try #sql(
        """
        CREATE TABLE "recurringTransactionsTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE,
          UNIQUE("recurringTransactionID", "tagID") ON CONFLICT IGNORE
        ) STRICT
        """
        )
        .execute(db)

        // Add recurringTransactionID to transactions table
        try #sql(
        """
        ALTER TABLE "transactions"
        ADD COLUMN "recurringTransactionID" TEXT REFERENCES "recurringTransactions"("id") ON DELETE SET NULL
        """
        )
        .execute(db)

        // Create indexes for foreign keys
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_recurringTransactionID"
        ON "recurringTransactionsCategories"("recurringTransactionID")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_categoryID"
        ON "recurringTransactionsCategories"("categoryID")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_recurringTransactionID"
        ON "recurringTransactionsTags"("recurringTransactionID")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_tagID"
        ON "recurringTransactionsTags"("tagID")
        """
        )
        .execute(db)

        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_transactions_recurringTransactionID"
        ON "transactions"("recurringTransactionID")
        """
        )
        .execute(db)

        // Index for querying active recurring transactions by next due date
        try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_recurringTransactions_status_nextDueDate"
        ON "recurringTransactions"("status", "nextDueDate")
        """
        )
        .execute(db)
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
    func dateInSameMonthAsNow(daysAgo: Int) -> Date {
        let candidate = calendar.startOfDay(for: now.addingTimeInterval(TimeInterval(-daysAgo * 24 * 60 * 60)))
        let candidateYM = calendar.dateComponents([.year, .month], from: candidate)
        if candidateYM.year == nowLocal.year, candidateYM.month == nowLocal.month {
            let base = calendar.startOfDay(for: candidate)
            return base
        } else {
            let fallback = calendar.startOfDay(for: thisMonthStart.addingTimeInterval(TimeInterval(min(daysAgo, 20) * 24 * 60 * 60)))
            return fallback
        }
    }

    func dateInPreviousMonth(dayOffsetFromStart: Int) -> Date {
        let base = calendar.startOfDay(for: previousMonthStart.addingTimeInterval(TimeInterval(dayOffsetFromStart * 24 * 60 * 60)))
        return base
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

    // Current month (~7 transactions, all within last 5 days to avoid future dates)
    let currentMonthSeed: [(daysAgo: Int, description: String, valueMinorUnits: Int, currencyCode: String, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
        (0, "Dinner at Alto El Fuego", 80_00, "USD", .expense, 1, [0, 1]),
        (0, "Coffee", 5_00, "USD", .expense, 1, [4]),
        (0, "Empanadas", 15000_00, "ARS", .expense, 1, [0]),  // ~$10 USD
        (1, "Groceries", 125_00, "USD", .expense, 0, [4]),
        (2, "Gym", 40_00, "USD", .expense, 4, [5, 4]),
        (3, "Taxi", 19_00, "USD", .expense, 5, []),
        (5, "Movie night", 17_00, "USD", .expense, 2, [0]),
    ]

    // Pre-calculate transaction data outside seed block
    var currentMonthTransactions: [(
        id: UUID,
        description: String,
        valueMinorUnits: Int,
        currencyCode: String,
        convertedValueMinorUnits: Int?,
        convertedCurrencyCode: String?,
        type: Transaction.TransactionType,
        createdAtUTC: Date,
        localYear: Int,
        localMonth: Int,
        localDay: Int,
        locationID: UUID,
        categoryID: String,
        tagIndices: [Int]
    )] = []

    for (index, seed) in currentMonthSeed.enumerated() {
        let id = uuid()
        let date = dateInSameMonthAsNow(daysAgo: seed.daysAgo)
        let local = date.localDateComponents()
        let locationID = locationIDs[index % locationIDs.count]

        // Calculate converted values
        let convertedValueMinorUnits: Int?
        let convertedCurrencyCode: String?
        if seed.currencyCode == "USD" {
            convertedValueMinorUnits = seed.valueMinorUnits
            convertedCurrencyCode = "USD"
        } else if seed.currencyCode == "ARS" {
            // 1 USD = 1500 ARS, so ARS to USD rate = 1/1500
            convertedValueMinorUnits = Int(Double(seed.valueMinorUnits) / 1500.0)
            convertedCurrencyCode = "USD"
        } else {
            convertedValueMinorUnits = nil
            convertedCurrencyCode = nil
        }

        currentMonthTransactions.append((
            id: id,
            description: seed.description,
            valueMinorUnits: seed.valueMinorUnits,
            currencyCode: seed.currencyCode,
            convertedValueMinorUnits: convertedValueMinorUnits,
            convertedCurrencyCode: convertedCurrencyCode,
            type: seed.type,
            createdAtUTC: date,
            localYear: local.year,
            localMonth: local.month,
            localDay: local.day,
            locationID: locationID,
            categoryID: categoryIDs[seed.categoryIndex],
            tagIndices: seed.tagIndices
        ))
    }

    // Previous month (a few)
    let previousMonthSeed: [(dayOffset: Int, description: String, valueMinorUnits: Int, currencyCode: String, type: Transaction.TransactionType, categoryIndex: Int, tagIndices: [Int])] = [
        (2, "Book", 19_00, "USD", .expense, 3, []),
        (6, "Dinner out", 54_00, "USD", .expense, 1, [0]),
        (14, "Internet bill", 60_00, "USD", .expense, 0, [4]),
        (21, "Side project", 420_00, "USD", .income, 6, [3]),
    ]

    // Pre-calculate transaction data outside seed block
    var previousMonthTransactions: [(
        id: UUID,
        description: String,
        valueMinorUnits: Int,
        currencyCode: String,
        convertedValueMinorUnits: Int?,
        convertedCurrencyCode: String?,
        type: Transaction.TransactionType,
        createdAtUTC: Date,
        localYear: Int,
        localMonth: Int,
        localDay: Int,
        locationID: UUID,
        categoryID: String,
        tagIndices: [Int]
    )] = []

    for (index, seed) in previousMonthSeed.enumerated() {
        let id = uuid()
        let date = dateInPreviousMonth(dayOffsetFromStart: seed.dayOffset)
        let local = date.localDateComponents()
        let locationID = locationIDs[(index + 3) % locationIDs.count]

        // Calculate converted values
        let convertedValueMinorUnits: Int?
        let convertedCurrencyCode: String?
        if seed.currencyCode == "USD" {
            convertedValueMinorUnits = seed.valueMinorUnits
            convertedCurrencyCode = "USD"
        } else if seed.currencyCode == "ARS" {
            convertedValueMinorUnits = Int(Double(seed.valueMinorUnits) / 1500.0)
            convertedCurrencyCode = "USD"
        } else {
            convertedValueMinorUnits = nil
            convertedCurrencyCode = nil
        }

        previousMonthTransactions.append((
            id: id,
            description: seed.description,
            valueMinorUnits: seed.valueMinorUnits,
            currencyCode: seed.currencyCode,
            convertedValueMinorUnits: convertedValueMinorUnits,
            convertedCurrencyCode: convertedCurrencyCode,
            type: seed.type,
            createdAtUTC: date,
            localYear: local.year,
            localMonth: local.month,
            localDay: local.day,
            locationID: locationID,
            categoryID: categoryIDs[seed.categoryIndex],
            tagIndices: seed.tagIndices
        ))
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

            // Insert current month transactions
            for t in currentMonthTransactions {
                Transaction(
                    id: t.id,
                    description: t.description,
                    valueMinorUnits: t.valueMinorUnits,
                    currencyCode: t.currencyCode,
                    convertedValueMinorUnits: t.convertedValueMinorUnits,
                    convertedCurrencyCode: t.convertedCurrencyCode,
                    type: t.type,
                    createdAtUTC: t.createdAtUTC,
                    localYear: t.localYear,
                    localMonth: t.localMonth,
                    localDay: t.localDay,
                    locationID: t.locationID
                )

                TransactionCategory.Draft(transactionID: t.id, categoryID: t.categoryID)
                for tagIndex in t.tagIndices {
                    TransactionTag.Draft(transactionID: t.id, tagID: tagIDs[tagIndex])
                }
            }

            // Insert previous month transactions
            for t in previousMonthTransactions {
                Transaction(
                    id: t.id,
                    description: t.description,
                    valueMinorUnits: t.valueMinorUnits,
                    currencyCode: t.currencyCode,
                    convertedValueMinorUnits: t.convertedValueMinorUnits,
                    convertedCurrencyCode: t.convertedCurrencyCode,
                    type: t.type,
                    createdAtUTC: t.createdAtUTC,
                    localYear: t.localYear,
                    localMonth: t.localMonth,
                    localDay: t.localDay,
                    locationID: t.locationID
                )

                TransactionCategory.Draft(transactionID: t.id, categoryID: t.categoryID)
                for tagIndex in t.tagIndices {
                    TransactionTag.Draft(transactionID: t.id, tagID: tagIDs[tagIndex])
                }
            }

            // Add exchange rates for ARS -> USD (today)
            let today = calendar.startOfDay(for: now)
            ExchangeRate(
                id: uuid(),
                fromCurrency: "ARS",
                toCurrency: "USD",
                rate: 1.0 / 1500.0,  // 1 USD = 1500 ARS
                date: today,
                fetchedAt: now
            )
            ExchangeRate(
                id: uuid(),
                fromCurrency: "USD",
                toCurrency: "ARS",
                rate: 1500.0,  // 1 ARS = 0.000667 USD
                date: today,
                fetchedAt: now
            )

            // MARK: - Recurring Transactions

            // 1. Monthly rent - due today
            RecurringTransaction(
                id: uuid(),
                description: "Rent",
                valueMinorUnits: 1500_00,
                currencyCode: "USD",
                type: .expense,
                frequency: RecurrenceFrequency.monthly.rawValue,
                interval: 1,
                weeklyDays: nil,
                monthlyMode: MonthlyMode.each.rawValue,
                monthlyDays: "1",
                monthlyOrdinal: nil,
                monthlyWeekday: nil,
                yearlyMonths: nil,
                yearlyDaysOfWeekEnabled: 0,
                yearlyOrdinal: nil,
                yearlyWeekday: nil,
                endMode: RecurrenceEndMode.never.rawValue,
                endDate: nil,
                endAfterOccurrences: nil,
                startDate: previousMonthStart,
                nextDueDate: today,
                postedCount: 1,
                status: .active,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )

            // 2. Weekly gym - overdue (3 days ago)
            let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
            RecurringTransaction(
                id: uuid(),
                description: "Gym Membership",
                valueMinorUnits: 40_00,
                currencyCode: "USD",
                type: .expense,
                frequency: RecurrenceFrequency.weekly.rawValue,
                interval: 1,
                weeklyDays: "2,4,6", // Mon, Wed, Fri
                monthlyMode: nil,
                monthlyDays: nil,
                monthlyOrdinal: nil,
                monthlyWeekday: nil,
                yearlyMonths: nil,
                yearlyDaysOfWeekEnabled: 0,
                yearlyOrdinal: nil,
                yearlyWeekday: nil,
                endMode: RecurrenceEndMode.never.rawValue,
                endDate: nil,
                endAfterOccurrences: nil,
                startDate: previousMonthStart,
                nextDueDate: threeDaysAgo,
                postedCount: 4,
                status: .active,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )

            // 3. Yearly subscription - due next week
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
            RecurringTransaction(
                id: uuid(),
                description: "iCloud Storage",
                valueMinorUnits: 2_99,
                currencyCode: "USD",
                type: .expense,
                frequency: RecurrenceFrequency.yearly.rawValue,
                interval: 1,
                weeklyDays: nil,
                monthlyMode: nil,
                monthlyDays: nil,
                monthlyOrdinal: nil,
                monthlyWeekday: nil,
                yearlyMonths: "1", // January
                yearlyDaysOfWeekEnabled: 0,
                yearlyOrdinal: nil,
                yearlyWeekday: nil,
                endMode: RecurrenceEndMode.never.rawValue,
                endDate: nil,
                endAfterOccurrences: nil,
                startDate: previousMonthStart,
                nextDueDate: nextWeek,
                postedCount: 0,
                status: .active,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )

            // 4. Paused Netflix subscription
            RecurringTransaction(
                id: uuid(),
                description: "Netflix",
                valueMinorUnits: 15_99,
                currencyCode: "USD",
                type: .expense,
                frequency: RecurrenceFrequency.monthly.rawValue,
                interval: 1,
                weeklyDays: nil,
                monthlyMode: MonthlyMode.onThe.rawValue,
                monthlyDays: nil,
                monthlyOrdinal: WeekdayOrdinal.first.rawValue,
                monthlyWeekday: Weekday.monday.rawValue,
                yearlyMonths: nil,
                yearlyDaysOfWeekEnabled: 0,
                yearlyOrdinal: nil,
                yearlyWeekday: nil,
                endMode: RecurrenceEndMode.never.rawValue,
                endDate: nil,
                endAfterOccurrences: nil,
                startDate: previousMonthStart,
                nextDueDate: today,
                postedCount: 2,
                status: .paused,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )
        }
    }
}
