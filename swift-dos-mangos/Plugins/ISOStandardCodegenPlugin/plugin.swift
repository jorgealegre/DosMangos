import PackagePlugin

@main
struct ISOCurrencies: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let dataInputURL = context.package.directoryURL.appending(path: "currencies.xml")
        let currencyRegistryURL = context.pluginWorkDirectoryURL.appending(path: "CurrencyRegistry.swift")

        return [
            .buildCommand(
                displayName: "Generating ISO 4217 Currency Registry",
                executable: try context.tool(named: "ISOStandardCodegen").url,
                arguments: [
                    dataInputURL.path(),
                    currencyRegistryURL.path()
                ],
                environment: [:],
                inputFiles: [
                    dataInputURL
                ],
                outputFiles: [
                    currencyRegistryURL
                ]
            )
        ]
    }
}
