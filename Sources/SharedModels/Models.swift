import CoreLocation
import Currency
import Dependencies
import Foundation
import SQLiteData

@Table
struct Transaction: Identifiable, Hashable, Sendable {
    let id: UUID

    var description: String

    // Original values (what user entered)
    var valueMinorUnits: Int
    var currencyCode: String

    // Converted values (for summaries/totals in default currency)
    // NULL = conversion not yet available (offline, rate not found, pending background job, etc.)
    var convertedValueMinorUnits: Int?
    var convertedCurrencyCode: String?

    var money: Money {
        get {
            Money(value: Int64(valueMinorUnits), currencyCode: currencyCode)
        }
        set {
            self.valueMinorUnits = Int(newValue.value)
            self.currencyCode = newValue.currencyCode
        }
    }

    /// Returns the converted money if available, nil otherwise
    var convertedMoney: Money? {
        guard let converted = convertedValueMinorUnits, let code = convertedCurrencyCode else {
            return nil
        }
        return Money(value: Int64(converted), currencyCode: code)
    }

    var signedMoney: Money {
        type == .expense ? money.negated() : money
    }

    var signedConvertedMoney: Money? {
        convertedMoney.map { type == .expense ? $0.negated() : $0 }
    }

    // TODO: To display the actual exchange rate used, we should join with the exchange_rates table
    // using the transaction's localDate and currency codes. The calculated rate from
    // convertedValue/originalValue is not reliable due to rounding of integer minor units.

    enum TransactionType: Int, QueryBindable, Sendable {
        case expense
        case income
    }
    var type: TransactionType

    /// Canonical instant (stored as a full timestamp in UTC).
    var createdAtUTC: Date

    /// Stable local calendar label captured at creation/edit time.
    ///
    /// This is used for grouping and month filtering so transactions don't shift days/months when the
    /// user travels across time zones.
    var localYear: Int
    var localMonth: Int
    var localDay: Int

    var localDate: Date {
        get {
            Date.localDate(year: localYear, month: localMonth, day: localDay)!
        }
        set {
            let local = newValue.localDateComponents()
            localYear = local.year
            localMonth = local.month
            localDay = local.day
        }
    }

    var locationID: UUID?
    var recurringTransactionID: UUID?
}
extension Transaction.Draft: Equatable {}
extension Transaction.Draft {
    var money: Money {
        get {
            Money(value: Int64(valueMinorUnits), currencyCode: currencyCode)
        }
        set {
            self.valueMinorUnits = Int(newValue.value)
            self.currencyCode = newValue.currencyCode
        }
    }

    var convertedMoney: Money? {
        guard let converted = convertedValueMinorUnits, let code = convertedCurrencyCode else {
            return nil
        }
        return Money(value: Int64(converted), currencyCode: code)
    }
}

extension Transaction.Draft {
    init() {
        @Dependency(\.date.now) var now
        let nowLocal = now.localDateComponents()

        self.init(
            description: "",
            valueMinorUnits: 0,
            currencyCode: "USD",
            convertedValueMinorUnits: nil,  // Will be filled when saved
            convertedCurrencyCode: nil,
            type: .expense,
            createdAtUTC: now,
            localYear: nowLocal.year,
            localMonth: nowLocal.month,
            localDay: nowLocal.day
        )
    }

    var localDate: Date {
        get {
            Date.localDate(year: localYear, month: localMonth, day: localDay)!
        }
        set {
            let local = newValue.localDateComponents()
            localYear = local.year
            localMonth = local.month
            localDay = local.day
        }
    }

    // 12300 <> "123"
    var valueText: String {
        get {
            let currency = CurrencyRegistry.currency(for: currencyCode)
            let divisor = pow(10.0, Double(currency.minorUnits))
            let wholeUnits = Double(valueMinorUnits) / divisor
            return wholeUnits != 0 ? String(Int(wholeUnits)) : ""
        }
        set {
            guard let value = Int(newValue) else {
                valueMinorUnits = 0
                return
            }
            let currency = CurrencyRegistry.currency(for: currencyCode)
            let multiplier = pow(10.0, Double(currency.minorUnits))
            valueMinorUnits = Int(Double(value) * multiplier)
        }
    }
}

// MARK: - Exchange Rate

@Table
struct ExchangeRate: Identifiable, Hashable, Sendable {
    let id: UUID
    var fromCurrency: String
    var toCurrency: String
    var rate: Double
    var date: Date  // The day this rate is for
    var fetchedAt: Date  // When we got it from API
}
extension ExchangeRate.Draft: Equatable {}

// MARK: - Category

@Table
struct Category: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var title: String

    var parentCategoryID: String?

    var id: String { title }

    var displayName: String {
        if let parentCategoryID {
            "\(parentCategoryID) › \(title)"
        } else {
            title
        }
    }
}
@Table("transactionsCategories")
struct TransactionCategory: Identifiable, Hashable, Sendable {
    let id: UUID
    var transactionID: UUID
    var categoryID: String
}
extension TransactionCategory.Draft: Equatable {}

@Table("transactionsCategoriesWithDisplayName")
struct TransactionCategoriesWithDisplayName {
    let id: UUID
    var transactionID: UUID
    var categoryID: String

    let displayName: String
}

// MARK: - Tag

@Table
struct Tag: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var title: String

    var id: String { title }
}
extension Tag?.TableColumns {
    var jsonTitles: some QueryExpression<[String].JSONRepresentation> {
        (self.title ?? "").jsonGroupArray(distinct: true, filter: self.title.isNot(nil))
    }
}
@Table("transactionsTags")
struct TransactionTag: Identifiable, Hashable, Sendable {
    let id: UUID
    var transactionID: UUID
    var tagID: String
}
extension TransactionTag.Draft: Equatable {}
extension Transaction {
    static let withTags = Self
        .group(by: \.id)
        .leftJoin(TransactionTag.all) { $0.id.eq($1.transactionID) }
        .leftJoin(Tag.all) { $1.tagID.eq($2.title) }
}

// MARK: - TransactionLocation

@Table("transaction_locations")
struct TransactionLocation: Identifiable, Hashable, Sendable {
    @Column("locationID")
    let id: UUID
    var latitude: Double
    var longitude: Double
    var city: String?
    var countryCode: String?

    var countryDisplayName: String? {
        guard let countryCode = countryCode else { return nil }
        @Dependency(\.locale) var locale
        return locale.localizedString(forRegionCode: countryCode)
    }
}
extension TransactionLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
extension TransactionLocation.Draft: Equatable {}
extension TransactionLocation.Draft {
    var countryDisplayName: String? {
        guard let countryCode = countryCode else { return nil }
        @Dependency(\.locale) var locale
        return locale.localizedString(forRegionCode: countryCode)
    }
}
extension TransactionLocation.Draft {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Recurring Transaction

enum RecurringTransactionStatus: Int, QueryBindable, Sendable {
    case active = 0
    case paused = 1
    case completed = 2
    case deleted = 3
}

@Table("recurringTransactions")
struct RecurringTransaction: Identifiable, Hashable, Sendable {
    let id: UUID

    var description: String
    var valueMinorUnits: Int
    var currencyCode: String
    var type: Transaction.TransactionType

    // MARK: Recurrence Rule (flattened)

    /// 0 = daily, 1 = weekly, 2 = monthly, 3 = yearly
    var frequency: Int
    /// Repeat every N units (e.g., every 2 weeks)
    var interval: Int
    /// Comma-separated weekday values: "2,4,6" for Mon, Wed, Fri (1=Sun, 2=Mon, ..., 7=Sat)
    var weeklyDays: String?
    /// 0 = each (specific days), 1 = onThe (ordinal weekday like "first Monday")
    var monthlyMode: Int?
    /// Comma-separated day numbers: "1,15" for 1st and 15th of month
    var monthlyDays: String?
    /// 1 = first, 2 = second, 3 = third, 4 = fourth, -1 = last
    var monthlyOrdinal: Int?
    /// 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var monthlyWeekday: Int?
    /// Comma-separated month numbers: "1,7" for January and July
    var yearlyMonths: String?
    /// 0 = false, 1 = true — when true, uses ordinal + weekday (e.g., "first Sunday of January")
    var yearlyDaysOfWeekEnabled: Int
    /// 1 = first, 2 = second, 3 = third, 4 = fourth, -1 = last
    var yearlyOrdinal: Int?
    /// 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var yearlyWeekday: Int?
    /// 0 = never, 1 = onDate, 2 = afterOccurrences
    var endMode: Int
    /// End date when endMode = 1 (onDate)
    var endDate: Date?
    /// Number of occurrences when endMode = 2 (afterOccurrences)
    var endAfterOccurrences: Int?

    // MARK: State

    /// When this recurrence begins (local date components)
    var startLocalYear: Int
    var startLocalMonth: Int
    var startLocalDay: Int

    /// The next occurrence to show as a virtual instance (local date components)
    var nextDueLocalYear: Int
    var nextDueLocalMonth: Int
    var nextDueLocalDay: Int

    /// How many transactions have been posted from this template
    var postedCount: Int
    /// 0 = active, 1 = paused, 2 = completed, 3 = deleted
    var status: RecurringTransactionStatus

    // MARK: Metadata

    var createdAtUTC: Date
    var updatedAtUTC: Date
}
extension RecurringTransaction.Draft: Equatable {}

extension RecurringTransaction {
    var startDate: Date {
        Date.localDate(year: startLocalYear, month: startLocalMonth, day: startLocalDay)!
    }

    var nextDueDate: Date {
        Date.localDate(year: nextDueLocalYear, month: nextDueLocalMonth, day: nextDueLocalDay)!
    }
}

extension RecurringTransaction.Draft {
    var startDate: Date {
        get {
            Date.localDate(year: startLocalYear, month: startLocalMonth, day: startLocalDay)!
        }
        set {
            let local = newValue.localDateComponents()
            startLocalYear = local.year
            startLocalMonth = local.month
            startLocalDay = local.day
        }
    }

    var nextDueDate: Date {
        get {
            Date.localDate(year: nextDueLocalYear, month: nextDueLocalMonth, day: nextDueLocalDay)!
        }
        set {
            let local = newValue.localDateComponents()
            nextDueLocalYear = local.year
            nextDueLocalMonth = local.month
            nextDueLocalDay = local.day
        }
    }
}

@Table("recurringTransactionsCategories")
struct RecurringTransactionCategory: Identifiable, Hashable, Sendable {
    let id: UUID
    var recurringTransactionID: UUID
    var categoryID: String
}
extension RecurringTransactionCategory.Draft: Equatable {}

@Table("recurringTransactionsTags")
struct RecurringTransactionTag: Identifiable, Hashable, Sendable {
    let id: UUID
    var recurringTransactionID: UUID
    var tagID: String
}
extension RecurringTransactionTag.Draft: Equatable {}

// MARK: - TransactionsListRow

@Table("transactionsListRows")
struct TransactionsListRow: Identifiable, Hashable, Sendable {
    var id: UUID { transaction.id }
    let transaction: Transaction
    let category: String?
    @Column(as: [String].JSONRepresentation.self)
    let tags: [String]
    let location: TransactionLocation?
}

// MARK: - Due Recurring Row

@Table("dueRecurringRows")
struct DueRecurringRow: Identifiable, Hashable, Sendable {
    var id: UUID { recurringTransaction.id }
    let recurringTransaction: RecurringTransaction
    let category: String?
    @Column(as: [String].JSONRepresentation.self)
    let tags: [String]
}

// Extension for building recurring transaction queries with tags
extension RecurringTransaction {
    static let withTags = Self
        .group(by: \.id)
        .leftJoin(RecurringTransactionTag.all) { $0.id.eq($1.recurringTransactionID) }
        .leftJoin(Tag.all) { $1.tagID.eq($2.title) }
}

extension RecurringTransactionTag?.TableColumns {
    var jsonTitles: some QueryExpression<[String].JSONRepresentation> {
        (self.tagID ?? "").jsonGroupArray(distinct: true, filter: self.tagID.isNot(nil))
    }
}

@Table("recurringTransactionCategoriesWithDisplayName")
struct RecurringTransactionCategoriesWithDisplayName {
    let id: UUID
    var recurringTransactionID: UUID
    var categoryID: String
    let displayName: String
}
