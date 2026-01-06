import Foundation

let arguments = ProcessInfo.processInfo.arguments
guard arguments.count == 5 else {
  print("Usage: ISOStandardCodegen <input.xml> <ISOCurrencies.swift> <CurrencyMint+Lookup.swift> <CurrencyMint+AllCurrencies.swift>")
  exit(65)
}

let isoStandardDefinitions = try parseDefinitions(at: URL(fileURLWithPath: arguments[1]))

try makeISOCurrencyDefinitionFile(at: URL(fileURLWithPath: arguments[2]), from: isoStandardDefinitions)
try makeMintISOCurrencySupportCodeFile(at: URL(fileURLWithPath: arguments[3]), from: isoStandardDefinitions)
try makeAllCurrenciesFile(at: URL(fileURLWithPath: arguments[4]), from: isoStandardDefinitions)
