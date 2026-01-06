import Foundation

func makeISOCurrencyDefinitionFile(at destinationURL: URL, from source: [CurrencyDefinition]) throws {
  let typeDefinitions = makeTypeDefinitions(from: source)
    .joined(separator: "\n\n")

  let fileContent = """
  \(makeFileHeader())

  import struct Foundation.Decimal

  \(typeDefinitions)
  """

  try fileContent.write(to: destinationURL, atomically: true, encoding: .utf8)
}

private func makeTypeDefinitions(from definitions: [CurrencyDefinition]) -> [String] {
  return definitions.map {
    definition in

    let summary: String = {
      let alphaIdentifier = definition.identifiers.alphabetic

      switch alphaIdentifier {
      case "XXX":
        return """
        /// The currency to represent a transaction where no currency was involved; as defined by ISO 4217.
        ///
        /// As ISO 4217 does not specify a minor unit for XXX, the value of `0` is used.
        """

      case "XTS":
        return """
        /// The currency suitable for testing; as defined by ISO 4217.
        ///
        /// As ISO 4217 does not specify a minor unit for XTS, the value of `1` is used for validating rounding errors.
        """

      default:
        return "/// The \(definition.name) (\(alphaIdentifier)) currency, as defined by ISO 4217."
      }
    }()

    let documentationFlag: String = {
#if swift(<5.8)
      return ""
#else
      return "@_documentation(visibility: private)"
#endif
    }()

    // Generate countries array
    let countriesArray: String = {
      if definition.countries.isEmpty {
        return "[]"
      }

      let countryLines = definition.countries.map { country in
        "      Country(name: \"\(country.name)\", flag: \"\(country.flag)\")"
      }

      return """
      [
      \(countryLines.joined(separator: ",\n"))
          ]
      """
    }()

    return """
    \(summary)
    \(documentationFlag)
    public struct \(definition.identifiers.alphabetic): CurrencyValue, CurrencyDescriptor {
      public static var name: String { "\(definition.name)" }
      public static var alphabeticCode: String { "\(definition.identifiers.alphabetic)" }
      public static var numericCode: UInt16 { \(definition.identifiers.numeric) }
      public static var minorUnits: UInt8 { \(definition.minorUnits) }
      public static var countries: [Country] {
        \(countriesArray)
      }

      public let exactAmount: Decimal

      public init(exactAmount: Decimal) { self.exactAmount = exactAmount }
    }
    """
  }
}
