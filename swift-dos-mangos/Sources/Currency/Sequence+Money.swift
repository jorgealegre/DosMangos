import Foundation

// MARK: - Sequence Extensions

extension Sequence where Element == Money {
  /// Returns the sum total of all money amounts in the sequence.
  ///
  /// Example:
  /// ```swift
  /// let amounts = [
  ///     Money(value: 1000, currencyCode: "USD"),
  ///     Money(value: 2500, currencyCode: "USD")
  /// ]
  /// let total = amounts.sum() // Money(value: 3500, currencyCode: "USD")
  /// ```
  ///
  /// - Precondition: All money values in the sequence must have the same currency code.
  /// - Returns: The sum of all money values, or `nil` if the sequence is empty.
  public func sum() -> Money? {
    var iterator = makeIterator()
    guard let first = iterator.next() else { return nil }

    var total = first
    while let next = iterator.next() {
      total = total + next // Will precondition-fail if currencies don't match
    }
    return total
  }

  /// Returns the sum total of all money amounts in the sequence that satisfy the given predicate.
  ///
  /// Example:
  /// ```swift
  /// let amounts = [
  ///     Money(value: 1000, currencyCode: "USD"),
  ///     Money(value: 5000, currencyCode: "USD"),
  ///     Money(value: 2500, currencyCode: "USD")
  /// ]
  /// let largeAmounts = amounts.sum(where: { $0.value > 2000 })
  /// // Money(value: 7500, currencyCode: "USD")
  /// ```
  ///
  /// - Precondition: All money values in the sequence must have the same currency code.
  /// - Parameter isIncluded: A closure that takes a money value and returns whether it should be included.
  /// - Returns: The sum of all money values that match the predicate, or `nil` if none match.
  public func sum(where isIncluded: (Money) throws -> Bool) rethrows -> Money? {
    var result: Money?

    for element in self {
      guard try isIncluded(element) else { continue }

      if let current = result {
        result = current + element
      } else {
        result = element
      }
    }

    return result
  }
}

