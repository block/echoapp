// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SPMExample",
    platforms: [
        .iOS(.v14),
        .macOS(.v14),
    ],
    dependencies: [
        .package(name: "echo", path: "../../"),
    ],
    targets: [
        .target(
            name: "SPMExample",
            dependencies: [
                .product(name: "EchoClient", package: "echo"),
            ]
        )
    ]
)
