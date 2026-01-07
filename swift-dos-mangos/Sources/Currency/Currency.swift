import struct Foundation.Decimal

/// Metadata describing a currency as defined by ISO 4217.
public struct Currency: Equatable, Hashable, Sendable {
  /// The ISO 4217 3-letter currency code (e.g., "USD").
  public let code: String

  /// The name of the currency (e.g., "US Dollar").
  public let name: String

  /// The number of decimal digits for minor units (e.g., 2 for cents).
  public let minorUnits: Int

  /// The countries that use this currency.
  public let countries: [Country]

  public init(code: String, name: String, minorUnits: Int, countries: [Country]) {
    self.code = code
    self.name = name
    self.minorUnits = minorUnits
    self.countries = countries
  }
}

