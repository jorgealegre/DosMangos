/// A type representing a country that uses a particular currency.
public struct Country: Hashable, Sendable {
  /// The name of the country as defined by ISO 4217.
  public let name: String

  /// The Unicode flag emoji representing the country.
  ///
  /// This is generated from the country's ISO 3166-1 alpha-2 code using
  /// regional indicator symbols (U+1F1E6 through U+1F1FF).
  ///
  /// For example, "🇺🇸" for the United States, "🇬🇧" for the United Kingdom.
  public let flag: String

  /// Creates a country instance.
  /// - Parameters:
  ///   - name: The name of the country.
  ///   - flag: The Unicode flag emoji for the country.
  public init(name: String, flag: String) {
    self.name = name
    self.flag = flag
  }
}

