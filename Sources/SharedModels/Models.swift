import Currency
import Foundation
import SQLiteData

@Table
struct Transaction: Identifiable, Hashable, Sendable {
    let id: UUID

    var description: String

    var valueMinorUnits: Int
    var currencyCode: String
    var value: USD {
        // TODO: hardcoded currency
        //        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
        return USD(minorUnits: Int64(valueMinorUnits))
    }

    var signedValue: USD {
        type == .expense ? value.negated() : value
    }

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
}
extension Transaction.Draft: Equatable {}
extension Transaction.Draft {
    var value: USD {
        // TODO: hardcoded currency
        return USD(minorUnits: Int64(valueMinorUnits))
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
        get { valueMinorUnits != 0 ? String(valueMinorUnits / 100) : "" }
        set {
            guard let value = Int(newValue) else {
                valueMinorUnits = 0
                return
            }
            valueMinorUnits = value * 100
        }
    }
}

// MARK: - Category

@Table
struct Category: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var title: String

    var parentCategoryID: String?

    var id: String { title }
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

// MARK: - TransactionsListRow

@Table("transactionsListRows")
struct TransactionsListRow: Identifiable, Hashable, Sendable {
    var id: UUID { transaction.id }
    let transaction: Transaction
    let category: String?
    @Column(as: [String].JSONRepresentation.self)
    let tags: [String]
}
