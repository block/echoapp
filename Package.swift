// swift-tools-version: 5.10

// ============================================================================
// PUBLIC ROOT MANIFEST — SDK
//
// This is the manifest external consumers pin (block/echoapp). It exposes the
// cross-platform SDK products: EchoClient, EchoPluginAPI, EchoDesktopPlugin,
// EchoConnection, and the optional client plugins.
//
// The macOS app, CLI tools, and desktop plugins live in EchoApp/Package.swift,
// which consumes this package as a local path dependency. That cross-package
// boundary is what lets the app link EchoPluginAPI/EchoPluginUI dynamically
// (one shared copy of type metadata between EchoApp.app and .echoplugin bundles)
// while everything else links statically. Do NOT fold the EchoApp targets back
// into this manifest: in a single package, Xcode links in-package target
// dependencies statically and refuses to also build the same targets
// dynamically for the .dynamic products below.
//
// Distribution-specific manifests may declare the SAME targets alongside
// additional integrations. KEEP THE MANIFESTS IN SYNC until a generator/check exists.
// ============================================================================

import PackageDescription

let package = Package(
    name: "echo",
    platforms: [
        .iOS(.v14),
        .macOS(.v14),
    ],
    products: [
        // .dynamic is required: the Echo app and .echoplugin bundles must share
        // a single copy of the EchoPluginAPI type metadata at runtime.
        .library(
            name: "EchoDesktopPlugin",
            type: .dynamic,
            targets: [
                "EchoPluginAPI",
                "EchoPluginUI",
            ]
        ),
        .library(
            name: "EchoPluginAPI",
            type: .dynamic,
            targets: ["EchoPluginAPI"]
        ),
        .library(
            name: "EchoClient",
            targets: ["EchoClient"]
        ),
        .library(
            name: "EchoConnection",
            targets: ["EchoConnection"]
        ),
        .library(
            name: "AccessibilityPlugin",
            targets: ["AccessibilityPlugin"]
        ),
        .library(
            name: "KeyValueStorePlugin",
            targets: ["KeyValueStorePlugin"]
        ),
        .executable(
            name: "TestClient",
            targets: ["TestClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nkristek/Highlight.git", from: "0.4.0"),
        .package(url: "https://github.com/cashapp/AccessibilitySnapshot", from: "0.12.1"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "EchoPluginAPI",
            dependencies: [],
            path: "Sources/EchoPluginAPI",
            exclude: [
                "Info.plist",
            ]
        ),
        .testTarget(
            name: "EchoPluginAPITests",
            dependencies: ["EchoPluginAPI"],
            path: "Tests/EchoPluginAPITests"
        ),
        .target(
            name: "EchoClient",
            dependencies: [
                "EchoConnection",
                "EchoPluginAPI",
            ],
            path: "Sources/EchoClient"
        ),
        .testTarget(
            name: "EchoClientTests",
            dependencies: [
                "EchoClient",
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/EchoClientTests"
        ),
        .target(
            name: "EchoConnection",
            dependencies: [],
            path: "Sources/EchoConnection"
        ),
        .target(
            name: "EchoPluginUI",
            dependencies: [
                "EchoPluginAPI",
                .product(name: "Highlight", package: "Highlight"),
            ],
            path: "Sources/EchoPluginUI"
        ),
        .target(
            name: "AccessibilityPlugin",
            dependencies: [
                "EchoPluginAPI",
                .product(
                    name: "AccessibilitySnapshotCore",
                    package: "AccessibilitySnapshot",
                    condition: .when(platforms: [.iOS])
                ),
                .product(
                    name: "AccessibilitySnapshotParser",
                    package: "AccessibilitySnapshot",
                    condition: .when(platforms: [.iOS])
                ),
            ],
            path: "Sources/OptionalPlugins/AccessibilityPlugin"
        ),
        .target(
            name: "KeyValueStorePlugin",
            dependencies: [
                "EchoPluginAPI",
            ],
            path: "Sources/OptionalPlugins/KeyValueStorePlugin"
        ),
        .executableTarget(
            name: "TestClient",
            dependencies: [
                "EchoClient",
            ],
            path: "Sources/TestClient"
        ),
    ]
)
