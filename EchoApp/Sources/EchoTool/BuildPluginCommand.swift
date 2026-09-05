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

        // Create the .echoplugin directory
        let pluginDirectory = outputDir.appendingPathComponent("\(pluginName).echoplugin", isDirectory: true)
        try execute(
            "/bin/mkdir",
            arguments: [
                "-p",
                pluginDirectory.path,
            ]
        )

        // Copy the plugin library into the .echoplugin directory
        let pluginDylibURL = pluginDirectory.appendingPathComponent("lib\(pluginName).dylib", isDirectory: false)
        try execute(
            "/bin/cp",
            arguments: [
                packageDir.appendingPathComponent(".build/release/lib\(pluginName).dylib", isDirectory: false).path,
                pluginDylibURL.path,
            ]
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
                pluginDylibURL.path,
            ]
        )

        // TODO: - codesign?
        // `security find-identity -v -p codesigning`
        // `codesign -s "Apple Development: ____ (___)"`

        Logger(subsystem: "xyz.block.echoapp.tool", category: "BuildPluginCommand")
            .info("Built plugin at \(pluginDirectory.path)")
    }

}
