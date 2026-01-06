import PackagePlugin

@main
struct ISOCurrencies: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let dataInputURL = context.package.directoryURL.appending(path: "currencies.xml")

        let currencyDefinitionURL = context.pluginWorkDirectoryURL.appending(path: "ISOCurrencies.swift")
        let mintLookupURL = context.pluginWorkDirectoryURL.appending(path: "CurrencyMint+ISOCurrencyLookup.swift")
        let allCurrenciesURL = context.pluginWorkDirectoryURL.appending(path: "CurrencyMint+AllCurrencies.swift")

        return [
            .buildCommand(
                displayName: "Generating ISO Standard currency support code",
                executable: try context.tool(named: "ISOStandardCodegen").url,
                arguments: [
                    dataInputURL.path(),
                    currencyDefinitionURL.path(),
                    mintLookupURL.path(),
                    allCurrenciesURL.path()
                ],
                environment: [:],
                inputFiles: [
                    dataInputURL
                ],
                outputFiles: [
                    currencyDefinitionURL,
                    mintLookupURL,
                    allCurrenciesURL
                ]
            )
        ]
    }
}
