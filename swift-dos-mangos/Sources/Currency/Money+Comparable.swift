import Foundation

// MARK: - Comparable

extension Money: Comparable {
  /// Compares two money values for ordering.
  ///
  /// - Precondition: Both values must have the same currency code.
  public static func < (lhs: Money, rhs: Money) -> Bool {
    precondition(lhs.currencyCode == rhs.currencyCode, "Cannot compare different currencies: \(lhs.currencyCode) and \(rhs.currencyCode)")
    return lhs.value < rhs.value
  }
}

