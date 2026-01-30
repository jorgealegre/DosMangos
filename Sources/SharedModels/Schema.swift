import Dependencies
import OSLog
import SQLiteData

@DatabaseFunction("uuid")
func uuid() -> UUID {
    @Dependency(\.uuid) var uuid
    return uuid()
}

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        defaultDatabase = try appDatabase()
//        defaultSyncEngine = try SyncEngine(
//            for: defaultDatabase,
//            tables: Transaction.self,
//            TransactionLocation.self,
//            privateTables:
//            Category.self,
//            Subcategory.self,
//            TransactionCategory.self,
//            Tag.self,
//            TransactionTag.self,
//            RecurringTransaction.self,
//            RecurringTransactionCategory.self,
//            RecurringTransactionTag.self
//            // ExchangeRate.self is ignored because it's just a local cache
//        )
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

        db.add(function: $uuid)
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

    migrator.registerAllMigrations()

    try migrator.migrate(database)

    try database.write { db in
        // TODO: triggers
    }

    return database
}

// MARK: - Views

@Table("allCategories")
struct AllCategories {
    let categoryID: Category.ID
    let subcategoryID: Subcategory.ID?
    let subcategoryTitle: String?
    let displayName: String
}

extension Database {
    func createViews() throws {

        try #sql("""
        CREATE TEMPORARY VIEW "allCategories" AS
        SELECT
            "categoryID", 
            "subcategoryID", 
            "subcategoryTitle", 
            CASE
                WHEN sc.\(Subcategory.columns.title) IS NOT NULL
                THEN s.\(Category.columns.title) || ' › ' || sc.\(Subcategory.columns.title)
                ELSE s.\(Category.columns.title)
            "displayName"
        FROM \(Category.self) c
        LEFT JOIN \(Subcategory.self) sc 
        ON \(Category.columns.primaryKey) = \(Subcategory.columns.categoryID)
        """)
        .execute(self)

        // View for transaction categories with display name
        // Handles both categoryID (references categories.title) and subcategoryID (references subcategories.id)
        try #sql("""
        CREATE TEMPORARY VIEW \(raw: TransactionCategoriesWithDisplayName.tableName) AS
        SELECT
            \(TransactionCategory.columns),
            CASE
                WHEN tc.\(raw: TransactionCategory.columns.categoryID.name) IS NOT NULL
                THEN tc.\(raw: TransactionCategory.columns.categoryID.name)
                WHEN tc.\(raw: TransactionCategory.columns.subcategoryID.name) IS NOT NULL
                THEN s.\(raw: Subcategory.columns.categoryID.name) || ' › ' || s.\(raw: Subcategory.columns.title.name)
                ELSE ''
            END AS \(raw: TransactionCategoriesWithDisplayName.columns.displayName.name)
        FROM \(raw: TransactionCategory.tableName) tc
        LEFT JOIN \(raw: Subcategory.tableName) s
        ON tc.\(raw: TransactionCategory.columns.subcategoryID.name) = s.\(raw: Subcategory.columns.id.name)
        """)
        .execute(self)

        try TransactionsListRow.createTemporaryView(
            as: Transaction
                .group(by: \.id)
                .leftJoin(TransactionCategoriesWithDisplayName.all) { $0.id.eq($1.transactionID) }
                .leftJoin(TransactionLocation.all) { $0.id.eq($2.transactionID) }
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

        // View for recurring transaction categories with display name
        try #sql("""
        CREATE TEMPORARY VIEW \(raw: RecurringTransactionCategoriesWithDisplayName.tableName) AS
        SELECT
            \(RecurringTransactionCategory.columns)
            CASE
                WHEN rtc.\(raw: RecurringTransactionCategory.columns.categoryID.name) IS NOT NULL
                THEN rtc.\(raw: RecurringTransactionCategory.columns.categoryID.name)
                WHEN rtc.\(raw: RecurringTransactionCategory.columns.subcategoryID.name) IS NOT NULL
                THEN s.\(raw: Subcategory.columns.categoryID.name) || ' › ' || s.\(raw: Subcategory.columns.title.name)
                ELSE ''
            END AS \(raw: RecurringTransactionCategoriesWithDisplayName.columns.displayName.name)
        FROM \(raw: RecurringTransactionCategory.tableName) rtc
        LEFT JOIN \(raw: Subcategory.tableName) s
        ON rtc.\(raw: RecurringTransactionCategory.columns.subcategoryID.name) = s.\(raw: Subcategory.columns.id.name)
        """)
        .execute(self)

        // View for due recurring rows (recurring transactions with category and tags)
        try DueRecurringRow.createTemporaryView(
            as: RecurringTransaction
                .group(by: \.id)
                .leftJoin(RecurringTransactionCategoriesWithDisplayName.all) { $0.id.eq($1.recurringTransactionID) }
                .withTags
                .select {
                    DueRecurringRow.Columns(
                        recurringTransaction: $0,
                        category: $1.displayName,
                        tags: $3.jsonTitles
                    )
                }
        )
        .execute(self)
    }
}

// TODO: db functions

nonisolated private let logger = Logger(subsystem: "dev.alegre.DosMangos", category: "Database")

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
    let subcategoriesMap: [String: [String]] = [
        "Home": ["Furniture", "Maintenance", "Utilities"],
        "Food & Drinks": ["Restaurants", "Groceries"]
    ]
    let standaloneCategories = ["Entertainment", "Transport", "Salary", "Health"]

    // Track category assignments for transactions
    // Each entry is either: (categoryTitle, nil) for top-level or (subcategoryTitle, subcategoryUUID)
    enum CategoryRef {
        case category(title: String)
        case subcategory(title: String, parentTitle: String, id: UUID)
    }

    // Build list of all category references for transaction assignment
    var categoryRefs: [CategoryRef] = []

    // Add parent categories as assignable
    for parentTitle in parentCategories {
        categoryRefs.append(.category(title: parentTitle))
    }

    // Add standalone categories
    for title in standaloneCategories {
        categoryRefs.append(.category(title: title))
    }

    // Add subcategories (need to generate UUIDs ahead of time)
    var subcategoryUUIDs: [(title: String, parentTitle: String, id: UUID)] = []
    for (parentTitle, subs) in subcategoriesMap {
        for subTitle in subs {
            let subID = uuid()
            subcategoryUUIDs.append((title: subTitle, parentTitle: parentTitle, id: subID))
            categoryRefs.append(.subcategory(title: subTitle, parentTitle: parentTitle, id: subID))
        }
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

    // Location data (indexed, will be created after transactions)
    let locations: [(latitude: Double, longitude: Double, city: String, countryCode: String)] = [
        (40.7128, -74.0060, "New York", "US"),
        (-34.6037, -58.3816, "Buenos Aires", "AR"),
        (51.5074, -0.1278, "London", "GB"),
        (35.6762, 139.6503, "Tokyo", "JP"),
        (-33.8688, 151.2093, "Sydney", "AU"),
        (48.8566, 2.3522, "Paris", "FR"),
        (19.0760, 72.8777, "Mumbai", "IN"),
    ]

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
        locationIndex: Int,
        categoryRefIndex: Int,
        tagIndices: [Int]
    )] = []

    for (index, seed) in currentMonthSeed.enumerated() {
        let id = uuid()
        let date = dateInSameMonthAsNow(daysAgo: seed.daysAgo)
        let local = date.localDateComponents()

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
            locationIndex: index % locations.count,
            categoryRefIndex: seed.categoryIndex,
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
        locationIndex: Int,
        categoryRefIndex: Int,
        tagIndices: [Int]
    )] = []

    for (index, seed) in previousMonthSeed.enumerated() {
        let id = uuid()
        let date = dateInPreviousMonth(dayOffsetFromStart: seed.dayOffset)
        let local = date.localDateComponents()

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
            locationIndex: (index + 3) % locations.count,
            categoryRefIndex: seed.categoryIndex,
            tagIndices: seed.tagIndices
        ))
    }

    // Helper to create transaction category based on CategoryRef
    func createTransactionCategory(transactionID: UUID, categoryRef: CategoryRef) -> TransactionCategory.Draft {
        switch categoryRef {
        case .category(let title):
            return TransactionCategory.Draft(transactionID: transactionID, categoryID: title, subcategoryID: nil)
        case .subcategory(_, _, let id):
            return TransactionCategory.Draft(transactionID: transactionID, categoryID: nil, subcategoryID: id)
        }
    }

    try database.write { db in
        try db.seed {
            for tagID in tagIDs {
                Tag(title: tagID)
            }

            // Create parent categories (top-level)
            for parentTitle in parentCategories {
                Category(title: parentTitle)
            }

            // Create standalone categories (also top-level)
            for title in standaloneCategories {
                Category(title: title)
            }

            // Create subcategories with pre-generated UUIDs
            for sub in subcategoryUUIDs {
                Subcategory(id: sub.id, title: sub.title, categoryID: sub.parentTitle)
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
                    localDay: t.localDay
                )

                // Create location for this transaction (shared PK pattern)
                let loc = locations[t.locationIndex]
                TransactionLocation(
                    transactionID: t.id,
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    city: loc.city,
                    countryCode: loc.countryCode
                )

                createTransactionCategory(transactionID: t.id, categoryRef: categoryRefs[t.categoryRefIndex])
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
                    localDay: t.localDay
                )

                // Create location for this transaction (shared PK pattern)
                let loc = locations[t.locationIndex]
                TransactionLocation(
                    transactionID: t.id,
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    city: loc.city,
                    countryCode: loc.countryCode
                )

                createTransactionCategory(transactionID: t.id, categoryRef: categoryRefs[t.categoryRefIndex])
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

            let previousMonthComponents = previousMonthStart.localDateComponents()
            let todayComponents = today.localDateComponents()

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
                startLocalYear: previousMonthComponents.year,
                startLocalMonth: previousMonthComponents.month,
                startLocalDay: previousMonthComponents.day,
                nextDueLocalYear: todayComponents.year,
                nextDueLocalMonth: todayComponents.month,
                nextDueLocalDay: todayComponents.day,
                postedCount: 1,
                status: .active,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )

            // 2. Weekly gym - overdue (3 days ago)
            let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
            let threeDaysAgoComponents = threeDaysAgo.localDateComponents()
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
                startLocalYear: previousMonthComponents.year,
                startLocalMonth: previousMonthComponents.month,
                startLocalDay: previousMonthComponents.day,
                nextDueLocalYear: threeDaysAgoComponents.year,
                nextDueLocalMonth: threeDaysAgoComponents.month,
                nextDueLocalDay: threeDaysAgoComponents.day,
                postedCount: 4,
                status: .active,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )

            // 3. Yearly subscription - due next week
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
            let nextWeekComponents = nextWeek.localDateComponents()
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
                startLocalYear: previousMonthComponents.year,
                startLocalMonth: previousMonthComponents.month,
                startLocalDay: previousMonthComponents.day,
                nextDueLocalYear: nextWeekComponents.year,
                nextDueLocalMonth: nextWeekComponents.month,
                nextDueLocalDay: nextWeekComponents.day,
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
                startLocalYear: previousMonthComponents.year,
                startLocalMonth: previousMonthComponents.month,
                startLocalDay: previousMonthComponents.day,
                nextDueLocalYear: todayComponents.year,
                nextDueLocalMonth: todayComponents.month,
                nextDueLocalDay: todayComponents.day,
                postedCount: 2,
                status: .paused,
                createdAtUTC: previousMonthStart,
                updatedAtUTC: now
            )
        }
    }
}
