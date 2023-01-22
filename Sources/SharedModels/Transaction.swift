import Foundation

public struct Transaction: Identifiable, Equatable {

    public enum TransactionType: Int {
        case expense
        case income
    }

    public var createdAt: Date
    public var description: String
    public let id: UUID
    public var value: Int
    public var transactionType: TransactionType

    public init(
        createdAt: Date,
        description: String,
        id: UUID = .init(),
        value: Int,
        transactionType: TransactionType
    ) {
        self.createdAt = createdAt
        self.description = description
        self.id = id
        self.value = value
        self.transactionType = transactionType
    }
}

public extension Transaction {
    static func mock(
        date: Date = Date(),
        transactionType: TransactionType = .expense
    ) -> Self {
        .init(
            createdAt: date,
            description: "Cigarettes",
            value: 12,
            transactionType: transactionType
        )
    }
}
