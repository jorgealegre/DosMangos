import Foundation

public struct Transaction: Identifiable, Equatable {
  public var description: String
  public let id: UUID
  public var value: Int

  public init(
    description: String,
    id: UUID = .init(),
    value: Int
  ) {
    self.description = description
    self.id = id
    self.value = value
  }
}
