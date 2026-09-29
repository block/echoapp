@testable import EchoTool

import XCTest

final class PluginBundleBuilderTests: XCTestCase {
    func test_build_createsLoaderCompatibleFrameworkBundle() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dylibURL = temporaryDirectory.appendingPathComponent("libCounterPlugin.dylib")
        let pluginInfoURL = temporaryDirectory.appendingPathComponent("PluginInfo.plist")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data("plugin".utf8).write(to: dylibURL)
        try Data("metadata".utf8).write(to: pluginInfoURL)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let output = try PluginBundleBuilder().build(
            pluginName: "CounterPlugin",
            bundleIdentifier: "com.example.echo.counter",
            dylibURL: dylibURL,
            pluginInfoURL: pluginInfoURL,
            outputDirectory: temporaryDirectory
        )

        let frameworkURL = output.bundleURL
            .appendingPathComponent("Contents/MacOS/CounterPlugin.framework")
        let frameworkBundle = try XCTUnwrap(Bundle(url: frameworkURL))
        let bundledPluginInfoURL = try XCTUnwrap(
            frameworkBundle.url(forResource: "PluginInfo", withExtension: "plist")
        )

        XCTAssertEqual(frameworkBundle.bundleIdentifier, "com.example.echo.counter")
        XCTAssertEqual(frameworkBundle.executableURL?.resolvingSymlinksInPath(), output.executableURL)
        XCTAssertEqual(try Data(contentsOf: output.executableURL), Data("plugin".utf8))
        XCTAssertEqual(try Data(contentsOf: bundledPluginInfoURL), Data("metadata".utf8))
    }
}
