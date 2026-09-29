import ArgumentParser
import Foundation
import os

struct BuildPluginCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "build-plugin",
        abstract: "Builds an Echo Plugin from source",
        discussion: """
        Output: SomePlugin.echoplugin
        """
    )

    @Argument(
        help: "The name of the plugin. Must match the name of a dynamic library in the plugin's Package.swift"
    )
    var pluginName: String

    @Option(
        help: "Output directory for the built Plugin.echoplugin bundle",
        completion: .directory
    )
    var outputDir: URL = URL(string: ".")!

    @Option(
        help: "The path to the Package.swift containing the Plugin library",
        completion: .file(extensions: ["swift"])
    )
    var packagePath: URL = URL(string: "Package.swift")!

    @Option(
        help: "A unique reverse-DNS identifier for the plugin framework"
    )
    var bundleIdentifier: String?

    func run() throws {
        let packageDir = packagePath.deletingLastPathComponent()

        // Build the Plugin library
        try execute(
            "/usr/bin/swift",
            arguments: [
                "build",
                "--package-path",
                packageDir.path.isEmpty ? "." : packageDir.path,
                "--product",
                pluginName,
                "--configuration",
                "release",
            ]
        )

        let buildProductsDirectory = packageDir.appendingPathComponent(".build/release", isDirectory: true)
        let builtDylibURL = buildProductsDirectory.appendingPathComponent("lib\(pluginName).dylib")
        let pluginInfoURL = try findPluginInfo(in: buildProductsDirectory)
        let pluginBundle = try PluginBundleBuilder().build(
            pluginName: pluginName,
            bundleIdentifier: bundleIdentifier ?? "xyz.block.echoapp.plugin.\(pluginName)",
            dylibURL: builtDylibURL,
            pluginInfoURL: pluginInfoURL,
            outputDirectory: outputDir
        )

        // EchoApp.app provides EchoPluginAPI via a framework,
        // but currently plugins are built as dylibs.
        // Use install_name_tool to tell the linker to resolve the EchoPluginAPI
        // dependency via Echo's framework instead of via a dylib.
        try execute(
            "/usr/bin/install_name_tool",
            arguments: [
                "-change",
                "@rpath/libEchoPluginAPI.dylib",
                "@rpath/EchoPluginAPI.framework/EchoPluginAPI",
                pluginBundle.executableURL.path,
            ]
        )

        // TODO: - codesign?
        // `security find-identity -v -p codesigning`
        // `codesign -s "Apple Development: ____ (___)"`

        Logger(subsystem: "xyz.block.echoapp.tool", category: "BuildPluginCommand")
            .info("Built plugin at \(pluginBundle.bundleURL.path)")
    }

}

// MARK: - Plugin Resources

private extension BuildPluginCommand {
    func findPluginInfo(in buildProductsDirectory: URL) throws -> URL {
        let resourceBundleSuffix = "_\(pluginName).bundle"
        let candidates = try FileManager.default
            .contentsOfDirectory(at: buildProductsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(resourceBundleSuffix) }
            .map { $0.appendingPathComponent("PluginInfo.plist") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard candidates.count == 1, let pluginInfoURL = candidates.first else {
            throw ValidationError(
                "Expected one PluginInfo.plist in a SwiftPM resource bundle ending in '\(resourceBundleSuffix)'; found \(candidates.count)."
            )
        }
        return pluginInfoURL
    }
}
