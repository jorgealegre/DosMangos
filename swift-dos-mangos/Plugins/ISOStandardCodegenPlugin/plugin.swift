import PackagePlugin

@main
struct ISOCurrencies: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let dataInputURL = context.package.directoryURL.appending(path: "ISO4217.json")

        let currencyDefinitionURL = context.pluginWorkDirectoryURL.appending(path: "ISOCurrencies.swift")
        let mintDefinitionURL = context.pluginWorkDirectoryURL.appending(path: "CurrencyMint+ISOCurrencyLookup.swift")

        return [
            .buildCommand(
                displayName: "Generating ISO Standard currency support code",
                executable: try context.tool(named: "ISOStandardCodegen").url,
                arguments: [
                    dataInputURL.path(),
                    currencyDefinitionURL.path(),
                    mintDefinitionURL.path()
                ],
                environment: [:],
                inputFiles: [
                    dataInputURL
                ],
                outputFiles: [
                    currencyDefinitionURL,
                    mintDefinitionURL
                ]
            )
        ]
    }
}
