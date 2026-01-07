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
    var convertedValueMinorUnits: Int
    var convertedCurrencyCode: String

    var money: Money {
        get {
            Money(value: Int64(valueMinorUnits), currencyCode: currencyCode)
        }
        set {
            self.valueMinorUnits = Int(newValue.value)
            self.currencyCode = newValue.currencyCode
        }
    }

    var convertedMoney: Money {
        Money(value: Int64(convertedValueMinorUnits), currencyCode: convertedCurrencyCode)
    }

    var signedMoney: Money {
        type == .expense ? money.negated() : money
    }

    var signedConvertedMoney: Money {
        type == .expense ? convertedMoney.negated() : convertedMoney
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

    var convertedMoney: Money {
        Money(value: Int64(convertedValueMinorUnits), currencyCode: convertedCurrencyCode)
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
            convertedValueMinorUnits: 0,
            convertedCurrencyCode: "USD",
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
