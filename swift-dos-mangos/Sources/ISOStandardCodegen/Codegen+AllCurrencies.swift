import Foundation

func makeAllCurrenciesFile(at destinationURL: URL, from currencies: [CurrencyDefinition]) throws {
  let currencyList = currencies
    .map { "    \($0.identifiers.alphabetic).self" }
    .joined(separator: ",\n")

  let fileContent = """
  \(makeFileHeader())

  extension CurrencyMint {
    /// Returns an array of all currency types defined by ISO 4217.
    ///
    /// This array contains all currency types that have been generated from the ISO 4217 specification.
    /// Each entry represents a unique currency, with its associated countries and metadata.
    ///
    /// - Returns: An array of currency descriptor types.
    public static var allCurrencies: [any CurrencyDescriptor.Type] {
      [
  \(currencyList)
      ]
    }
  }
  """

  try fileContent.write(to: destinationURL, atomically: true, encoding: .utf8)
}

