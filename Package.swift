// swift-tools-version: 5.7

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")

let package = Package(
    name: "DosMangos",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "AddTransactionFeature", targets: ["AddTransactionFeature"]),
        .library(name: "SharedModels", targets: ["SharedModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.45.0"),
    ],
    targets: [
        .target(name: "AppFeature", dependencies: [tca, "AddTransactionFeature", "SharedModels"]),
        .target(name: "AddTransactionFeature", dependencies: [tca, "SharedModels"]),
        .target(name: "SharedModels", dependencies: []),
    ]
)
