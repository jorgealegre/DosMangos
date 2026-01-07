import Foundation

// MARK: - Arithmetic Operations

extension Money {
  /// Returns the sum of two money values.
  ///
  /// - Precondition: Both values must have the same currency code.
  public static func + (lhs: Money, rhs: Money) -> Money {
    precondition(lhs.currencyCode == rhs.currencyCode, "Cannot add different currencies: \(lhs.currencyCode) and \(rhs.currencyCode)")
    return Money(value: lhs.value + rhs.value, currencyCode: lhs.currencyCode)
  }

  /// Adds two money values in place.
  ///
  /// - Precondition: Both values must have the same currency code.
  public static func += (lhs: inout Money, rhs: Money) {
    lhs = lhs + rhs
  }

  /// Returns the difference of two money values.
  ///
  /// - Precondition: Both values must have the same currency code.
  public static func - (lhs: Money, rhs: Money) -> Money {
    precondition(lhs.currencyCode == rhs.currencyCode, "Cannot subtract different currencies: \(lhs.currencyCode) and \(rhs.currencyCode)")
    return Money(value: lhs.value - rhs.value, currencyCode: lhs.currencyCode)
  }

  /// Subtracts two money values in place.
  ///
  /// - Precondition: Both values must have the same currency code.
  public static func -= (lhs: inout Money, rhs: Money) {
    lhs = lhs - rhs
  }

  /// Multiplies a money value by a decimal multiplier.
  ///
  /// Example:
  /// ```swift
  /// let price = Money(value: 1000, currencyCode: "USD") // $10.00
  /// let tax = price * 0.09 // $0.90
  /// ```
  public static func * (lhs: Money, rhs: Decimal) -> Money {
    Money(amount: lhs.amount * rhs, currencyCode: lhs.currencyCode)
  }

  /// Multiplies a money value by a decimal multiplier in place.
  public static func *= (lhs: inout Money, rhs: Decimal) {
    lhs = lhs * rhs
  }

  /// Divides a money value by a decimal divisor.
  ///
  /// Example:
  /// ```swift
  /// let total = Money(value: 1000, currencyCode: "USD") // $10.00
  /// let perPerson = total / 3 // $3.33
  /// ```
  public static func / (lhs: Money, rhs: Decimal) -> Money {
    Money(amount: lhs.amount / rhs, currencyCode: lhs.currencyCode)
  }

  /// Divides a money value by a decimal divisor in place.
  public static func /= (lhs: inout Money, rhs: Decimal) {
    lhs = lhs / rhs
  }
}

