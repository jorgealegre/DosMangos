import Foundation

let arguments = ProcessInfo.processInfo.arguments
guard arguments.count == 3 else {
  print("Usage: ISOStandardCodegen <input.xml> <CurrencyRegistry+Generated.swift>")
  exit(65)
}

let isoStandardDefinitions = try parseDefinitions(at: URL(fileURLWithPath: arguments[1]))

try makeCurrencyRegistryFile(at: URL(fileURLWithPath: arguments[2]), from: isoStandardDefinitions)
