import Foundation

func makeCurrencyRegistryFile(at destinationURL: URL, from currencies: [CurrencyDefinition]) throws {
  let currencyEntries = currencies
    .map { currency in
      let countriesArray = currency.countries
        .map { country in
          "      Country(name: \"\(country.name)\", flag: \"\(country.flag)\")"
        }
        .joined(separator: ",\n")

      return """
          "\(currency.identifiers.alphabetic)": Currency(
            code: "\(currency.identifiers.alphabetic)",
            name: "\(currency.name)",
            minorUnits: \(currency.minorUnits),
            countries: [
      \(countriesArray)
            ]
          )
      """
    }
    .joined(separator: ",\n")

  let fileContent = """
  \(makeFileHeader())

  /// Registry of all ISO 4217 currencies.
  public enum CurrencyRegistry {
    /// All available currencies, keyed by currency code.
    ///
    /// This is a compile-time constant populated from `currencies.xml`.
    public static let all: [String: Currency] = [
  \(currencyEntries)
    ]

    /// Returns the currency for the given currency code.
    /// Falls back to a generic currency if the code is not found.
    public static func currency(for code: String) -> Currency {
      all[code] ?? Currency(
        code: code,
        name: code,
        minorUnits: 2,
        countries: []
      )
    }

    // MARK: Common Currencies (for convenience)

    public static var USD: Currency { currency(for: "USD") }
    public static var EUR: Currency { currency(for: "EUR") }
    public static var GBP: Currency { currency(for: "GBP") }
    public static var JPY: Currency { currency(for: "JPY") }
    public static var AUD: Currency { currency(for: "AUD") }
    public static var CAD: Currency { currency(for: "CAD") }
    public static var CHF: Currency { currency(for: "CHF") }
    public static var CNY: Currency { currency(for: "CNY") }
    public static var ARS: Currency { currency(for: "ARS") }
    public static var BRL: Currency { currency(for: "BRL") }
    public static var MXN: Currency { currency(for: "MXN") }
  }
  """

  try fileContent.write(to: destinationURL, atomically: true, encoding: .utf8)
}

