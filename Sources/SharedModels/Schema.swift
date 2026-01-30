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

extension Database {
    func createViews() throws {

        try TransactionsListRow.createTemporaryView(
            as: Transaction
                .group(by: \.id)
                .leftJoin(TransactionCategory.all) { $0.id.eq($1.transactionID) }
                .leftJoin(Subcategory.all) { $1.subcategoryID.eq($2.id) }
                .leftJoin(TransactionLocation.all) { $0.id.eq($3.transactionID) }
                .withTags
                .select {
                    TransactionsListRow.Columns(
                        transaction: $0,
                        categoryDisplayName: #sql("\($2.categoryID) || ' › ' || \($2.title)"),
                        tags: $5.jsonTitles,
                        location: $3
                    )
                }
        )
        .execute(self)

        try DueRecurringRow.createTemporaryView(
            as: RecurringTransaction
                .group(by: \.id)
                .leftJoin(RecurringTransactionCategory.all) { $0.id.eq($1.recurringTransactionID) }
                .leftJoin(Subcategory.all) { $1.subcategoryID.eq($2.id) }
                .withTags
                .select {
                    DueRecurringRow.Columns(
                        recurringTransaction: $0,
                        subcategoryID: $1.subcategoryID,
                        categoryDisplayName: #sql("\($2.categoryID) || ' › ' || \($2.title)"),
                        tags: $4.jsonTitles
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

    // Categories (grouping containers)
    let categories = ["Housing", "Food & Drinks", "Entertainment", "Transport", "Income", "Health"]

    // Subcategories (assignable to transactions)
    // Order matters - indices used in transaction seed data below
    let subcategoriesMap: [(category: String, subcategories: [String])] = [
        ("Housing", ["Rent", "Gardening", "Furniture", "Utilities"]),        // 0-3
        ("Food & Drinks", ["Dinner", "Coffee", "Groceries"]),                // 4-6
        ("Entertainment", ["Movies", "Books"]),                              // 7-8
        ("Transport", ["Fuel", "Taxi"]),                                     // 9-10
        ("Income", ["Salary", "Side Projects"]),                             // 11-12
        ("Health", ["Gym", "Pharmacy"]),                                     // 13-14
    ]

    // Build list of all subcategories with pre-generated UUIDs for transaction assignment
    var allSubcategories: [(title: String, categoryTitle: String, id: UUID)] = []
    for (categoryTitle, subs) in subcategoriesMap {
        for subTitle in subs {
            allSubcategories.append((title: subTitle, categoryTitle: categoryTitle, id: uuid()))
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

    // Subcategory indices (based on allSubcategories order):
    // Housing: 0=Rent, 1=Gardening, 2=Furniture, 3=Utilities
    // Food & Drinks: 4=Dinner, 5=Coffee, 6=Groceries
    // Entertainment: 7=Movies, 8=Books
    // Transport: 9=Fuel, 10=Taxi
    // Income: 11=Salary, 12=Side Projects
    // Health: 13=Gym, 14=Pharmacy

    // Current month (~7 transactions, all within last 5 days to avoid future dates)
    let currentMonthSeed: [(daysAgo: Int, description: String, valueMinorUnits: Int, currencyCode: String, type: Transaction.TransactionType, subcategoryIndex: Int, tagIndices: [Int])] = [
        (0, "Dinner at Alto El Fuego", 80_00, "USD", .expense, 4, [0, 1]),   // Dinner
        (0, "Coffee", 5_00, "USD", .expense, 5, [4]),                         // Coffee
        (0, "Empanadas", 15000_00, "ARS", .expense, 4, [0]),                  // Dinner
        (1, "Groceries", 125_00, "USD", .expense, 6, [4]),                    // Groceries
        (2, "Gym", 40_00, "USD", .expense, 13, [5, 4]),                       // Gym
        (3, "Taxi", 19_00, "USD", .expense, 10, []),                          // Taxi
        (5, "Movie night", 17_00, "USD", .expense, 7, [0]),                   // Movies
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
        subcategoryIndex: Int,
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
            subcategoryIndex: seed.subcategoryIndex,
            tagIndices: seed.tagIndices
        ))
    }

    // Previous month (a few)
    let previousMonthSeed: [(dayOffset: Int, description: String, valueMinorUnits: Int, currencyCode: String, type: Transaction.TransactionType, subcategoryIndex: Int, tagIndices: [Int])] = [
        (2, "Book", 19_00, "USD", .expense, 8, []),            // Books
        (6, "Dinner out", 54_00, "USD", .expense, 4, [0]),     // Dinner
        (14, "Internet bill", 60_00, "USD", .expense, 3, [4]), // Utilities
        (21, "Side project", 420_00, "USD", .income, 12, [3]), // Side Projects
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
        subcategoryIndex: Int,
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
            subcategoryIndex: seed.subcategoryIndex,
            tagIndices: seed.tagIndices
        ))
    }

    try database.write { db in
        try db.seed {
            for tagID in tagIDs {
                Tag(title: tagID)
            }

            // Create categories (grouping containers)
            for title in categories {
                Category(title: title)
            }

            // Create subcategories with pre-generated UUIDs
            for sub in allSubcategories {
                Subcategory(id: sub.id, title: sub.title, categoryID: sub.categoryTitle)
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

                TransactionCategory.Draft(transactionID: t.id, subcategoryID: allSubcategories[t.subcategoryIndex].id)
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

                TransactionCategory.Draft(transactionID: t.id, subcategoryID: allSubcategories[t.subcategoryIndex].id)
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
