import Foundation

public struct Transaction: Identifiable, Equatable {

    public enum TransactionType: Int {
        case expense
        case income
    }

    public var absoluteValue: Int
    public var createdAt: Date
    public var description: String
    public let id: UUID
    public var transactionType: TransactionType

    public init(
        absoluteValue: Int,
        createdAt: Date,
        description: String,
        id: UUID = .init(),
        transactionType: TransactionType
    ) {
        self.absoluteValue = absoluteValue
        self.createdAt = createdAt
        self.description = description
        self.id = id
        self.transactionType = transactionType
    }

    public var value: Int {
        switch transactionType {
        case .expense:
            return -absoluteValue
        case .income:
            return absoluteValue
        }
    }
}

public extension Transaction {
    static func mock(
        date: Date = Date(),
        transactionType: TransactionType = .expense
    ) -> Self {
        .init(
            absoluteValue: 12,
            createdAt: date,
            description: "Cigarettes",
            transactionType: transactionType
        )
    }
}
