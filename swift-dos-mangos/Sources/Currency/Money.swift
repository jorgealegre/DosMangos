import Foundation

/// A monetary amount with an associated currency.
public struct Money: Equatable, Hashable, Sendable {
  /// The monetary value in the smallest currency unit.
  ///
  /// This is stored as an integer to avoid floating-point precision issues:
  /// - USD: 1050 = $10.50 (cents)
  /// - JPY: 1050 = ¥1050 (yen, no decimals)
  /// - BHD: 1050 = 1.050 BD (fils, 3 decimal places)
  public let value: Int64

  /// The ISO 4217 currency code (e.g., "USD", "EUR", "ARS").
  public let currencyCode: String

  /// The currency metadata for this money's currency.
  public var currency: Currency {
    CurrencyRegistry.currency(for: currencyCode)
  }

  /// Creates money with a value in the smallest currency unit.
  /// - Parameters:
  ///   - value: The amount in smallest units (e.g., 1050 cents = $10.50 USD)
  ///   - currencyCode: The ISO 4217 currency code
  public init(value: Int64, currencyCode: String) {
    self.value = value
    self.currencyCode = currencyCode
  }

  /// Creates money from a decimal amount.
  /// - Parameters:
  ///   - amount: The decimal amount (e.g., 10.50 for $10.50)
  ///   - currencyCode: The ISO 4217 currency code
  public init(amount: Decimal, currencyCode: String) {
    let descriptor = CurrencyRegistry.currency(for: currencyCode)
    let multiplier = pow(Decimal(10), descriptor.minorUnits)
    var result = amount * multiplier
    var rounded = Decimal()
    NSDecimalRound(&rounded, &result, 0, .bankers)
    self.value = Int64(truncating: rounded as NSNumber)
    self.currencyCode = currencyCode
  }

  /// The decimal amount (e.g., 10.50 for a value of 1050 in USD).
  public var amount: Decimal {
    let divisor = pow(Decimal(10), currency.minorUnits)
    return Decimal(value) / divisor
  }

  /// Returns a negated version of this money.
  public func negated() -> Money {
    Money(value: -value, currencyCode: currencyCode)
  }

  /// Converts this money to another currency using the provided exchange rate.
  /// - Parameters:
  ///   - targetCurrency: The currency code to convert to.
  ///   - rate: The exchange rate (1 unit of this currency = rate units of target currency).
  /// - Returns: The converted money amount.
  public func converted(to targetCurrency: String, rate: Decimal) -> Money {
    let convertedAmount = amount * rate
    return Money(amount: convertedAmount, currencyCode: targetCurrency)
  }
}

