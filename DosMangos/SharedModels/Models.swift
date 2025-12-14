import Currency
import Foundation
@_exported import SQLiteData

@Table
struct Transaction: Identifiable, Hashable, Sendable {
    let id: UUID

    var description: String

    var valueMinorUnits: Int
    var currencyCode: String
    var value: USD {
        return USD(integerLiteral: valueMinorUnits)
//        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
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
}
extension Transaction.Draft: Equatable {}
extension Transaction.Draft {
    var value: USD {
        return USD(integerLiteral: valueMinorUnits)
//        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
    }
}

@Table
struct Category: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var title: String

    var id: String { title }
}

@Table
struct Tag: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var title: String

    var id: String { title }
}

@Table("transactionsCategories")
struct TransactionCategory: Identifiable, Hashable, Sendable {
    let id: UUID
    var transactionID: UUID
    var categoryID: String
}
extension TransactionCategory.Draft: Equatable {}

@Table("transactionsTags")
struct TransactionTag: Identifiable, Hashable, Sendable {
    let id: UUID
    var transactionID: UUID
    var tagID: String
}
extension TransactionTag.Draft: Equatable {}
