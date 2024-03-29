// swift-tools-version: 5.7

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
let xctestDynamicOverlay = Target.Dependency.product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "TransactionsFeature", targets: ["TransactionsFeature"]),
        .library(name: "TransactionsStore", targets: ["TransactionsStore"]),
        .library(name: "AddTransactionFeature", targets: ["AddTransactionFeature"]),
        .library(name: "SharedModels", targets: ["SharedModels"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.50.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "0.8.2")
    ],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: [
                tca,
                "TransactionsFeature",
                "SharedModels"
            ]
        ),
        .target(
            name: "TransactionsFeature",
            dependencies: [
                tca,
                "AddTransactionFeature",
                "TransactionsStore",
                "SharedModels"
            ]
        ),
        .target(
            name: "TransactionsStore",
            dependencies: [
                dependencies,
                xctestDynamicOverlay,
                "SharedModels"
            ]
        ),
        .target(
            name: "AddTransactionFeature",
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
