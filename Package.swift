// swift-tools-version: 5.9

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
let xctestDynamicOverlay = Target.Dependency.product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "TransactionsFeature", targets: ["TransactionsFeature"]),
        .library(name: "TransactionsStore", targets: ["TransactionsStore"]),
        .library(name: "AddTransactionFeature", targets: ["AddTransactionFeature"]),
        .library(name: "SharedModels", targets: ["SharedModels"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.2")
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
