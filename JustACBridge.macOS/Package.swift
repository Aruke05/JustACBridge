// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "JustACBridgeMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "JustACBridgeMac", targets: ["JustACBridgeMac"])
    ],
    targets: [
        .executableTarget(
            name: "JustACBridgeMac",
            path: "Sources/JustACBridgeMac"
        )
    ]
)
