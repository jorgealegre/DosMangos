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
extension Category?.TableColumns {
    var jsonTitles: some QueryExpression<[String].JSONRepresentation> {
        (self.title ?? "").jsonGroupArray(distinct: true, filter: self.title.isNot(nil))
    }
}
@Table("transactionsCategories")
struct TransactionCategory: Identifiable, Hashable, Sendable {
    let id: UUID
    var transactionID: UUID
    var categoryID: String
}
extension TransactionCategory.Draft: Equatable {}
extension Transaction {
    static let withCategories = Self
        .group(by: \.id)
        .leftJoin(TransactionCategory.all) { $0.id.eq($1.transactionID) }
        .leftJoin(Category.all) { $1.categoryID.eq($2.title) }
}

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
