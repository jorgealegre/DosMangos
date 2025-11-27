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

    var createdAt: Date
}
extension Transaction.Draft: Equatable {}
extension Transaction.Draft {
    var value: USD {
        return USD(integerLiteral: valueMinorUnits)
//        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
    }
}
