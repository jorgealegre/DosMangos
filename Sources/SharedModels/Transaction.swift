import Foundation

public struct Transaction: Identifiable, Equatable {
    public var date: Date
    public var description: String
    public let id: UUID
    public var value: Int

    public init(
        date: Date,
        description: String,
        id: UUID = .init(),
        value: Int
    ) {
        self.date = date
        self.description = description
        self.id = id
        self.value = value
    }
}

public extension Transaction {
    static func mock(date: Date = Date()) -> Self {
        .init(
            date: date,
            description: "Cigarettes",
            value: 12
        )
    }
}
