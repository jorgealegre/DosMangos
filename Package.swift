// swift-tools-version: 6.2

import PackageDescription

let currency = Target.Dependency.product(name: "Currency", package: "swift-currency")
let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
let dependenciesMacros = Target.Dependency.product(name: "DependenciesMacros", package: "swift-dependencies")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "TransactionForm", targets: ["TransactionForm"]),
        .library(name: "TransactionsList", targets: ["TransactionsList"]),
        .library(name: "SharedModels", targets: ["SharedModels"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.3.0"),
        .package(url: "https://github.com/peek-travel/swift-currency", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                tca,
                "TransactionForm",
                "TransactionsList",
                "SharedModels"
            ]
        ),
        .target(
            name: "TransactionsList",
            dependencies: [
                currency,
                tca,
                "SharedModels"
            ]
        ),
        .target(
            name: "TransactionForm",
            dependencies: [
                currency,
                tca,
                "SharedModels"
            ]
        ),
        .target(
            name: "SharedModels",
            dependencies: [
                currency,
                .product(name: "SQLiteData", package: "sqlite-data")
            ]
        )
    ]
)
