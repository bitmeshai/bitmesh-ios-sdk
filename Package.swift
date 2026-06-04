// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Bitmesh",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
    ],
    products: [
        .library(name: "Bitmesh", targets: ["Bitmesh"]),
    ],
    targets: [
        .target(name: "Bitmesh"),
        .testTarget(
            name: "BitmeshTests",
            dependencies: ["Bitmesh"],
            resources: [.process("Fixtures")]
        ),
    ]
)
