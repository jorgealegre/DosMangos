import Foundation

func parseDefinitions(at file: URL) throws -> [CurrencyDefinition] {
  let xmlData = try Data(contentsOf: file)

  let parser = CurrencyXMLParser()
  let xmlParser = XMLParser(data: xmlData)
  xmlParser.delegate = parser

  guard xmlParser.parse() else {
    throw NSError(domain: "XMLParsingError", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Failed to parse XML"
    ])
  }

  return parser.currencyDefinitions
}

struct CountryInfo: Hashable {
  let name: String
  let flag: String
}

struct CurrencyDefinition {
  let name: String
  let identifiers: (alphabetic: String, numeric: Int)
  let minorUnits: Int
  let countries: [CountryInfo]
}

// MARK: - XML Parser Delegate

private class CurrencyXMLParser: NSObject, XMLParserDelegate {
  var currencyDefinitions: [CurrencyDefinition] = []

  // Temporary storage for current entry
  private var currentCountryName: String?
  private var currentCurrencyName: String?
  private var currentCurrencyCode: String?
  private var currentNumericCode: Int?
  private var currentMinorUnits: Int?
  private var currentElementValue: String = ""

  // Group entries by currency code
  private var entriesByCurrency: [String: (name: String, numeric: Int, minorUnits: Int, countries: Set<String>)] = [:]

  func parserDidEndDocument(_ parser: XMLParser) {
    // Convert grouped entries to CurrencyDefinitions
    currencyDefinitions = entriesByCurrency.map { currencyCode, info in
      let countries = info.countries.sorted().map { countryName in
        CountryInfo(name: countryName, flag: generateFlagEmoji(for: countryName))
      }

      return CurrencyDefinition(
        name: info.name,
        identifiers: (alphabetic: currencyCode, numeric: info.numeric),
        minorUnits: info.minorUnits,
        countries: countries
      )
    }.sorted { $0.identifiers.alphabetic < $1.identifiers.alphabetic }
  }

  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    currentElementValue = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentElementValue += string
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    let trimmedValue = currentElementValue.trimmingCharacters(in: .whitespacesAndNewlines)

    switch elementName {
    case "CtryNm":
      currentCountryName = trimmedValue
    case "CcyNm":
      currentCurrencyName = trimmedValue
    case "Ccy":
      currentCurrencyCode = trimmedValue
    case "CcyNbr":
      currentNumericCode = Int(trimmedValue)
    case "CcyMnrUnts":
      currentMinorUnits = Int(trimmedValue)
    case "CcyNtry":
      // End of an entry - process it
      if let code = currentCurrencyCode,
         let name = currentCurrencyName,
         let numeric = currentNumericCode,
         let minorUnits = currentMinorUnits,
         let countryName = currentCountryName {

        if var existing = entriesByCurrency[code] {
          // Add country to existing currency
          existing.countries.insert(countryName)
          entriesByCurrency[code] = existing
        } else {
          // New currency
          entriesByCurrency[code] = (
            name: name,
            numeric: numeric,
            minorUnits: minorUnits,
            countries: [countryName]
          )
        }
      }

      // Reset for next entry
      currentCountryName = nil
      currentCurrencyName = nil
      currentCurrencyCode = nil
      currentNumericCode = nil
      currentMinorUnits = nil
    default:
      break
    }

    currentElementValue = ""
  }
}

// MARK: - Flag Emoji Generation

private func generateFlagEmoji(for countryName: String) -> String {
  let countryCode = mapCountryNameToCode(countryName)
  return flagEmoji(from: countryCode)
}

private func flagEmoji(from countryCode: String) -> String {
  let code = countryCode.uppercased()
  guard code.count == 2 else { return "" }

  var emoji = ""
  for scalar in code.unicodeScalars {
    guard let regionalIndicator = UnicodeScalar(0x1F1E6 + scalar.value - 0x41) else {
      return ""
    }
    emoji.append(String(regionalIndicator))
  }
  return emoji
}

private func mapCountryNameToCode(_ name: String) -> String {
  let uppercasedName = name.uppercased()

  // Common country mappings
  let mappings: [String: String] = [
    "UNITED STATES OF AMERICA (THE)": "US",
    "UNITED KINGDOM OF GREAT BRITAIN AND NORTHERN IRELAND (THE)": "GB",
    "UNITED ARAB EMIRATES (THE)": "AE",
    "AFGHANISTAN": "AF",
    "ALBANIA": "AL",
    "ALGERIA": "DZ",
    "AMERICAN SAMOA": "AS",
    "ANDORRA": "AD",
    "ANGOLA": "AO",
    "ANGUILLA": "AI",
    "ANTIGUA AND BARBUDA": "AG",
    "ARGENTINA": "AR",
    "ARMENIA": "AM",
    "ARUBA": "AW",
    "AUSTRALIA": "AU",
    "AUSTRIA": "AT",
    "AZERBAIJAN": "AZ",
    "BAHAMAS (THE)": "BS",
    "BAHRAIN": "BH",
    "BANGLADESH": "BD",
    "BARBADOS": "BB",
    "BELARUS": "BY",
    "BELGIUM": "BE",
    "BELIZE": "BZ",
    "BENIN": "BJ",
    "BERMUDA": "BM",
    "BHUTAN": "BT",
    "BOLIVIA (PLURINATIONAL STATE OF)": "BO",
    "BONAIRE, SINT EUSTATIUS AND SABA": "BQ",
    "BOSNIA AND HERZEGOVINA": "BA",
    "BOTSWANA": "BW",
    "BOUVET ISLAND": "BV",
    "BRAZIL": "BR",
    "BRITISH INDIAN OCEAN TERRITORY (THE)": "IO",
    "BRUNEI DARUSSALAM": "BN",
    "BULGARIA": "BG",
    "BURKINA FASO": "BF",
    "BURUNDI": "BI",
    "CABO VERDE": "CV",
    "CAMBODIA": "KH",
    "CAMEROON": "CM",
    "CANADA": "CA",
    "CAYMAN ISLANDS (THE)": "KY",
    "CENTRAL AFRICAN REPUBLIC (THE)": "CF",
    "CHAD": "TD",
    "CHILE": "CL",
    "CHINA": "CN",
    "CHRISTMAS ISLAND": "CX",
    "COCOS (KEELING) ISLANDS (THE)": "CC",
    "COLOMBIA": "CO",
    "COMOROS (THE)": "KM",
    "CONGO (THE DEMOCRATIC REPUBLIC OF THE)": "CD",
    "CONGO (THE)": "CG",
    "COOK ISLANDS (THE)": "CK",
    "COSTA RICA": "CR",
    "CÔTE D'IVOIRE": "CI",
    "CROATIA": "HR",
    "CUBA": "CU",
    "CURAÇAO": "CW",
    "CYPRUS": "CY",
    "CZECHIA": "CZ",
    "DENMARK": "DK",
    "DJIBOUTI": "DJ",
    "DOMINICA": "DM",
    "DOMINICAN REPUBLIC (THE)": "DO",
    "ECUADOR": "EC",
    "EGYPT": "EG",
    "EL SALVADOR": "SV",
    "EQUATORIAL GUINEA": "GQ",
    "ERITREA": "ER",
    "ESTONIA": "EE",
    "ESWATINI": "SZ",
    "ETHIOPIA": "ET",
    "EUROPEAN UNION": "EU",
    "FALKLAND ISLANDS (THE) [MALVINAS]": "FK",
    "FAROE ISLANDS (THE)": "FO",
    "FIJI": "FJ",
    "FINLAND": "FI",
    "FRANCE": "FR",
    "FRENCH GUIANA": "GF",
    "FRENCH POLYNESIA": "PF",
    "FRENCH SOUTHERN TERRITORIES (THE)": "TF",
    "GABON": "GA",
    "GAMBIA (THE)": "GM",
    "GEORGIA": "GE",
    "GERMANY": "DE",
    "GHANA": "GH",
    "GIBRALTAR": "GI",
    "GREECE": "GR",
    "GREENLAND": "GL",
    "GRENADA": "GD",
    "GUADELOUPE": "GP",
    "GUAM": "GU",
    "GUATEMALA": "GT",
    "GUERNSEY": "GG",
    "GUINEA": "GN",
    "GUINEA-BISSAU": "GW",
    "GUYANA": "GY",
    "HAITI": "HT",
    "HEARD ISLAND AND McDONALD ISLANDS": "HM",
    "HOLY SEE (THE)": "VA",
    "HONDURAS": "HN",
    "HONG KONG": "HK",
    "HUNGARY": "HU",
    "ICELAND": "IS",
    "INDIA": "IN",
    "INDONESIA": "ID",
    "IRAN (ISLAMIC REPUBLIC OF)": "IR",
    "IRAQ": "IQ",
    "IRELAND": "IE",
    "ISLE OF MAN": "IM",
    "ISRAEL": "IL",
    "ITALY": "IT",
    "JAMAICA": "JM",
    "JAPAN": "JP",
    "JERSEY": "JE",
    "JORDAN": "JO",
    "KAZAKHSTAN": "KZ",
    "KENYA": "KE",
    "KIRIBATI": "KI",
    "KOREA (THE DEMOCRATIC PEOPLE'S REPUBLIC OF)": "KP",
    "KOREA (THE REPUBLIC OF)": "KR",
    "KUWAIT": "KW",
    "KYRGYZSTAN": "KG",
    "LAO PEOPLE'S DEMOCRATIC REPUBLIC (THE)": "LA",
    "LATVIA": "LV",
    "LEBANON": "LB",
    "LESOTHO": "LS",
    "LIBERIA": "LR",
    "LIBYA": "LY",
    "LIECHTENSTEIN": "LI",
    "LITHUANIA": "LT",
    "LUXEMBOURG": "LU",
    "MACAO": "MO",
    "NORTH MACEDONIA": "MK",
    "MADAGASCAR": "MG",
    "MALAWI": "MW",
    "MALAYSIA": "MY",
    "MALDIVES": "MV",
    "MALI": "ML",
    "MALTA": "MT",
    "MARSHALL ISLANDS (THE)": "MH",
    "MARTINIQUE": "MQ",
    "MAURITANIA": "MR",
    "MAURITIUS": "MU",
    "MAYOTTE": "YT",
    "MEXICO": "MX",
    "MICRONESIA (FEDERATED STATES OF)": "FM",
    "MOLDOVA (THE REPUBLIC OF)": "MD",
    "MONACO": "MC",
    "MONGOLIA": "MN",
    "MONTENEGRO": "ME",
    "MONTSERRAT": "MS",
    "MOROCCO": "MA",
    "MOZAMBIQUE": "MZ",
    "MYANMAR": "MM",
    "NAMIBIA": "NA",
    "NAURU": "NR",
    "NEPAL": "NP",
    "NETHERLANDS (THE)": "NL",
    "NEW CALEDONIA": "NC",
    "NEW ZEALAND": "NZ",
    "NICARAGUA": "NI",
    "NIGER (THE)": "NE",
    "NIGERIA": "NG",
    "NIUE": "NU",
    "NORFOLK ISLAND": "NF",
    "NORTHERN MARIANA ISLANDS (THE)": "MP",
    "NORWAY": "NO",
    "OMAN": "OM",
    "PAKISTAN": "PK",
    "PALAU": "PW",
    "PANAMA": "PA",
    "PAPUA NEW GUINEA": "PG",
    "PARAGUAY": "PY",
    "PERU": "PE",
    "PHILIPPINES (THE)": "PH",
    "PITCAIRN": "PN",
    "POLAND": "PL",
    "PORTUGAL": "PT",
    "PUERTO RICO": "PR",
    "QATAR": "QA",
    "RÉUNION": "RE",
    "ROMANIA": "RO",
    "RUSSIAN FEDERATION (THE)": "RU",
    "RWANDA": "RW",
    "SAINT BARTHÉLEMY": "BL",
    "SAINT HELENA, ASCENSION AND TRISTAN DA CUNHA": "SH",
    "SAINT KITTS AND NEVIS": "KN",
    "SAINT LUCIA": "LC",
    "SAINT MARTIN (FRENCH PART)": "MF",
    "SAINT PIERRE AND MIQUELON": "PM",
    "SAINT VINCENT AND THE GRENADINES": "VC",
    "SAMOA": "WS",
    "SAN MARINO": "SM",
    "SAO TOME AND PRINCIPE": "ST",
    "SAUDI ARABIA": "SA",
    "SENEGAL": "SN",
    "SERBIA": "RS",
    "SEYCHELLES": "SC",
    "SIERRA LEONE": "SL",
    "SINGAPORE": "SG",
    "SINT MAARTEN (DUTCH PART)": "SX",
    "SLOVAKIA": "SK",
    "SLOVENIA": "SI",
    "SOLOMON ISLANDS": "SB",
    "SOMALIA": "SO",
    "SOUTH AFRICA": "ZA",
    "SOUTH SUDAN": "SS",
    "SPAIN": "ES",
    "SRI LANKA": "LK",
    "SUDAN (THE)": "SD",
    "SURINAME": "SR",
    "SVALBARD AND JAN MAYEN": "SJ",
    "SWEDEN": "SE",
    "SWITZERLAND": "CH",
    "SYRIAN ARAB REPUBLIC": "SY",
    "TAIWAN (PROVINCE OF CHINA)": "TW",
    "TAJIKISTAN": "TJ",
    "TANZANIA, UNITED REPUBLIC OF": "TZ",
    "THAILAND": "TH",
    "TIMOR-LESTE": "TL",
    "TOGO": "TG",
    "TOKELAU": "TK",
    "TONGA": "TO",
    "TRINIDAD AND TOBAGO": "TT",
    "TUNISIA": "TN",
    "TÜRK İYE": "TR",
    "TURKMENISTAN": "TM",
    "TURKS AND CAICOS ISLANDS (THE)": "TC",
    "TUVALU": "TV",
    "UGANDA": "UG",
    "UKRAINE": "UA",
    "URUGUAY": "UY",
    "UZBEKISTAN": "UZ",
    "VANUATU": "VU",
    "VENEZUELA (BOLIVARIAN REPUBLIC OF)": "VE",
    "VIET NAM": "VN",
    "VIRGIN ISLANDS (BRITISH)": "VG",
    "VIRGIN ISLANDS (U.S.)": "VI",
    "WALLIS AND FUTUNA": "WF",
    "WESTERN SAHARA": "EH",
    "YEMEN": "YE",
    "ZAMBIA": "ZM",
    "ZIMBABWE": "ZW",
    "ÅLAND ISLANDS": "AX"
  ]

  return mappings[uppercasedName] ?? ""
}
