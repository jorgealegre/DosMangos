// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "MoneyTracker",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "AppFeature", dependencies: []),
    ]
)
