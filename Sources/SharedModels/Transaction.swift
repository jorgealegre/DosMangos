import Currency
import Foundation
@_exported import SQLiteData

@Table
public struct Transaction: Identifiable, Hashable, Sendable {
    public let id: UUID

    public var description: String

    public var valueMinorUnits: Int
    public var currencyCode: String
    public var value: USD {
        return USD(integerLiteral: valueMinorUnits)
//        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
    }

    public enum TransactionType: Int, QueryBindable, Sendable {
        case expense
        case income
    }
    public var type: TransactionType

    public var createdAt: Date
}
extension Transaction.Draft: Equatable {}
extension Transaction.Draft {
    public var value: USD {
        return USD(integerLiteral: valueMinorUnits)
//        CurrencyMint.standard.make(identifier: .alphaCode(currencyCode), minorUnits: Int64(valueMinorUnits))!
    }
}
