// swift-tools-version: 5.7

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-composable-architecture")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "TransactionsFeature", targets: ["TransactionsFeature"]),
        .library(name: "TransactionsStore", targets: ["TransactionsStore"]),
        .library(name: "AddTransactionFeature", targets: ["AddTransactionFeature"]),
        .library(name: "SharedModels", targets: ["SharedModels"]),
        .library(name: "Sqlite", targets: ["Sqlite"]),
        .library(name: "FileClient", targets: ["FileClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.48.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "0.8.0")
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
        .systemLibrary(
            name: "Csqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
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
                tca,
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
                "SharedModels",
                "Sqlite"
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
        ),
        .target(
            name: "FileClient",
            dependencies: [
                dependencies,
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay")
            ]
        ),
        .target(
            name: "Sqlite",
            dependencies: [
                .target(name: "Csqlite3")
            ]
        ),
    ]
)
