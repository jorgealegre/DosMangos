// swift-tools-version: 6.1

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
let dependenciesMacros = Target.Dependency.product(name: "DependenciesMacros", package: "swift-dependencies")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "TransactionForm", targets: ["TransactionForm"]),
        .library(name: "TransactionsList", targets: ["TransactionsList"]),
        .library(name: "SharedModels", targets: ["SharedModels"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0")
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
                tca,
                "SharedModels"
            ]
        ),
        .target(
            name: "TransactionForm",
            dependencies: [
                tca,
                "SharedModels"
            ]
        ),
        .target(
            name: "SharedModels",
            dependencies: [
            ]
        )
    ]
)
