// swift-tools-version: 5.7

import PackageDescription

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")

let package = Package(
    name: "MoneyTracker",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "AddTransactionFeature", targets: ["AddTransactionFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.45.0"),
    ],
    targets: [
        .target(name: "AppFeature", dependencies: [tca, "AddTransactionFeature"]),
        .target(name: "AddTransactionFeature", dependencies: [tca]),
    ]
)
