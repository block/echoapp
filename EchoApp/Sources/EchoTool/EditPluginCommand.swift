import ArgumentParser
import Foundation
import RegexBuilder
import XcodeProj

struct EditPluginCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit and debug an Echo Plugin package in Xcode"
    )

    @Argument(
        help: "The path to the Package.swift containing the Plugin library",
        completion: .file(extensions: ["swift"])
    )
    var packagePath: URL

    @Option(
        help: "The path to EchoApp.app",
        completion: .file(extensions: ["swift"])
    )
    var echoPath: URL = URL(string: "/Applications/EchoApp.app")!

    func run() throws {
        let pluginNames = try findPluginNamesFromPackage()
        try pluginNames.forEach(generateDebugScheme)
        try openXcode()
    }

    // MARK: - Private Methods

    /// Finds all the Plugin libraries in the provided package.
    private func findPluginNamesFromPackage() throws -> [String] {
        let pluginNameReference = Reference(Substring.self)

        let pluginRegex = Regex {
            "library("
            ZeroOrMore(.whitespace)
            "name:"
            ZeroOrMore(.whitespace)
            "\""
            Capture(as: pluginNameReference) {
                OneOrMore(.word)
            }
            "\""
        }
        do {
            let packageContents = try String(contentsOf: packagePath)
            return packageContents.matches(of: pluginRegex).map { String($0[pluginNameReference]) }
        } catch {
            throw ValidationError("Failed find plugins in Package.swift at \(packagePath.path)")
        }
    }

    /// Generate an XCScheme in the .swiftpm directory for debugging the specified plugin
    private func generateDebugScheme(for pluginName: String) throws {
        let echoToolPath = Bundle.main.executablePath!
        let outputDir = "~/Library/Application Support/Echo/Plugins"

        let killEchoScript = "pkill -9 'Echo'"

        let buildPluginScript = """
        "\(echoToolPath)" build-plugin \(pluginName) --output-dir "\(outputDir)" --package-path "\(packagePath.path)"
        """

        let scheme = XCScheme(
            name: "Debug \(pluginName)",
            lastUpgradeVersion: "1420",
            version: "1.3",
            buildAction: XCScheme.BuildAction(
                buildActionEntries: [
                    .init(
                        buildableReference: .init(
                            referencedContainer: "container:",
                            blueprint: nil,
                            buildableName: pluginName,
                            blueprintName: pluginName
                        ),
                        buildFor: [.running]
                    )
                ]
            ),
            launchAction: XCScheme.LaunchAction(
                runnable: nil,
                buildConfiguration: "Debug",
                preActions: [
                    XCScheme.ExecutionAction(scriptText: killEchoScript, title: "Kill Echo"),
                    XCScheme.ExecutionAction(scriptText: buildPluginScript, title: "Build Plugin"),
                ],
                pathRunnable: XCScheme.PathRunnable(filePath: echoPath.path)
            )
        )
        let packageDirectory = packagePath.deletingLastPathComponent()
        let schemePath = packageDirectory.appending(
            path: ".swiftpm/xcode/xcshareddata/xcschemes/Debug \(pluginName).xcscheme"
        )
        try FileManager.default.createDirectory(
            at: schemePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try scheme.write(path: .init(schemePath.path), override: true)
    }

    private func openXcode() throws {
        try execute(
            "/usr/bin/xed",
            arguments: [packagePath.path]
        )
    }

}
