// swift-tools-version: 5.10

// ============================================================================
// ECHO APP PACKAGE — macOS app, CLI tools, and desktop plugins
//
// App.xcodeproj references this package. It consumes the SDK (../Package.swift)
// as a local path dependency so that EchoPluginAPI/EchoPluginUI arrive via the
// .dynamic EchoDesktopPlugin product: Xcode builds ONE EchoDesktopPlugin
// framework that the app embeds and that .echoplugin bundles bind to at
// runtime. Never depend on the SDK's EchoPluginAPI/EchoPluginUI targets
// directly from here — that would statically duplicate their type metadata in
// the app and crash plugin loading.
//
// Distribution-specific manifests may declare the SAME targets alongside
// additional integrations. KEEP THE MANIFESTS IN SYNC until a generator/check exists.
// ============================================================================

import PackageDescription

let package = Package(
    name: "echo-app",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Echo",
            targets: ["Echo"]
        ),
        .executable(
            name: "echo-tool",
            targets: ["EchoTool"]
        ),
        .executable(
            name: "echoapp",
            targets: ["EchoCLI"]
        ),
        .library(
            name: "AnalyticsDesktopPlugin",
            targets: ["AnalyticsDesktopPlugin"]
        ),
        .library(
            name: "AppInfoDesktopPlugin",
            targets: ["AppInfoDesktopPlugin"]
        ),
        .library(
            name: "LoggingDesktopPlugin",
            targets: ["LoggingDesktopPlugin"]
        ),
        .library(
            name: "KeyValueStoreDesktopPlugin",
            targets: ["KeyValueStoreDesktopPlugin"]
        ),
        .library(
            name: "NetworkingDesktopPlugin",
            targets: ["NetworkingDesktopPlugin"]
        ),
        .library(
            name: "EchoMCP",
            targets: ["EchoMCP"]
        ),
        .library(
            name: "AccessibilityDesktopPlugin",
            targets: ["AccessibilityDesktopPlugin"]
        ),
        .library(
            name: "NavigationDesktopPlugin",
            targets: ["NavigationDesktopPlugin"]
        ),
        .library(
            name: "DebugMenuDesktopPlugin",
            targets: ["DebugMenuDesktopPlugin"]
        ),
        .library(
            name: "CrashReportingDesktopPlugin",
            targets: ["CrashReportingDesktopPlugin"]
        ),
    ],
    dependencies: [
        .package(name: "echo", path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.23.2")),
        .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "8.0.0")),
        .package(url: "https://github.com/vapor/vapor", .upToNextMajor(from: "4.122.1")),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.0"),
        // Explicit override: swift-numerics 1.0.3 (from Vapor's swift-crypto) is incompatible
        // with Xcode 26 — _NumericsShims moved. 1.1.1 fixes this.
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.1.1"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "Echo",
            dependencies: [
                .product(name: "EchoConnection", package: "echo"),
                .product(name: "EchoDesktopPlugin", package: "echo"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "AnalyticsDesktopPlugin",
                "AppInfoDesktopPlugin",
                "LoggingDesktopPlugin",
                "KeyValueStoreDesktopPlugin",
                "NetworkingDesktopPlugin",
                "AccessibilityDesktopPlugin",
                "NavigationDesktopPlugin",
                "DebugMenuDesktopPlugin",
                "CrashReportingDesktopPlugin",
                "EchoMCP",
            ],
            path: "Sources/Echo",
            swiftSettings: [
                // The internal root manifest still ships the executable as echo-cli.
                .define("ECHOAPP_PUBLIC_DISTRIBUTION"),
            ]
        ),
        .testTarget(
            name: "EchoTests",
            dependencies: ["Echo"],
            path: "Tests/EchoTests"
        ),
        .executableTarget(
            name: "EchoTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ],
            path: "Sources/EchoTool"
        ),
        .testTarget(
            name: "EchoToolTests",
            dependencies: ["EchoTool"],
            path: "Tests/EchoToolTests"
        ),
        .executableTarget(
            name: "EchoCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "EchoConnection", package: "echo"),
                .product(name: "EchoPluginAPI", package: "echo"),
                .product(name: "Vapor", package: "vapor"),
                "DebugMenuPluginAPI",
            ],
            path: "Sources/EchoCLI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "EchoCLITests",
            dependencies: ["EchoCLI"],
            path: "Tests/EchoCLITests"
        ),
        // MARK: - Foundational Desktop Plugins
        .target(
            name: "AppInfoDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/AppInfo/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "AnalyticsDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
                "EchoMCP",
            ],
            path: "Sources/Plugins/Analytics/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "AccessibilityDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/Accessibility/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
                .copy("accessibility.png"),
            ]
        ),
        .target(
            name: "NavigationDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/Navigation/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "LoggingDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/Logging/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "KeyValueStoreDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/KeyValueStore/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "DebugMenuPluginAPI",
            path: "Sources/Plugins/DebugMenu/API",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "DebugMenuPluginAPITests",
            dependencies: ["DebugMenuPluginAPI"],
            path: "Tests/DebugMenuPluginAPITests"
        ),
        .target(
            name: "DebugMenuDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
                "DebugMenuPluginAPI",
            ],
            path: "Sources/Plugins/DebugMenu/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "CrashReportingDesktopPlugin",
            dependencies: [
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/Plugins/CrashReporting/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .target(
            name: "EchoMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "EchoDesktopPlugin", package: "echo"),
            ],
            path: "Sources/EchoMCP",
            resources: [
                .copy("Resources/echo-mcp"),
            ]
        ),
        .target(
            name: "NetworkingDesktopPlugin",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "EchoDesktopPlugin", package: "echo"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Vapor", package: "vapor"),
                "EchoMCP",
            ],
            path: "Sources/Plugins/Networking/Desktop",
            resources: [
                .copy("PluginInfo.plist"),
                .copy("README.md"),
            ]
        ),
        .testTarget(
            name: "NetworkingDesktopPluginTests",
            dependencies: [
                "NetworkingDesktopPlugin",
                "AnalyticsDesktopPlugin",
                "EchoMCP",
            ],
            path: "Tests/NetworkingDesktopPluginTests"
        ),
        .testTarget(
            name: "NavigationDesktopPluginTests",
            dependencies: ["NavigationDesktopPlugin"],
            path: "Tests/NavigationDesktopPluginTests"
        ),
    ]
)
