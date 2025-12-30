// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "swift-dos-mangos",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "CoreLocationClient",
            targets: ["CoreLocationClient"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.10.0")
    ],
    targets: [
        .target(
            name: "CoreLocationClient",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "CoreLocationClientTests",
            dependencies: ["CoreLocationClient"]
        ),
    ]
)
