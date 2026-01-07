// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "swift-dos-mangos",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
        .tvOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "CoreLocationClient", targets: ["CoreLocationClient"]),
        .library(name: "Currency", targets: ["Currency"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
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
        .target(
            name: "Currency",
            dependencies: [],
            plugins: ["ISOStandardCodegenPlugin"]
        ),
        .executableTarget(name: "ISOStandardCodegen"),
        .plugin(
            name: "ISOStandardCodegenPlugin",
            capability: .buildTool(),
            dependencies: ["ISOStandardCodegen"]
        )
    ]
)
