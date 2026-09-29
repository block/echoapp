import Foundation

struct PluginBundleBuilder {
    struct Output {
        let bundleURL: URL
        let executableURL: URL
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func build(
        pluginName: String,
        bundleIdentifier: String,
        dylibURL: URL,
        pluginInfoURL: URL,
        outputDirectory: URL
    ) throws -> Output {
        let bundleURL = outputDirectory.appendingPathComponent("\(pluginName).echoplugin", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let frameworkURL = contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("\(pluginName).framework", isDirectory: true)
        let versionURL = frameworkURL
            .appendingPathComponent("Versions", isDirectory: true)
            .appendingPathComponent("A", isDirectory: true)
        let resourcesURL = versionURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = versionURL.appendingPathComponent(pluginName, isDirectory: false)

        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: dylibURL, to: executableURL)
        try fileManager.copyItem(
            at: pluginInfoURL,
            to: resourcesURL.appendingPathComponent("PluginInfo.plist")
        )
        try writePropertyList(
            [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleIdentifier": "\(bundleIdentifier).bundle",
                "CFBundleName": pluginName,
                "CFBundlePackageType": "BNDL",
                "CFBundleSupportedPlatforms": ["MacOSX"],
            ],
            to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        )
        try writePropertyList(
            [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleExecutable": pluginName,
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": pluginName,
                "CFBundlePackageType": "FMWK",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "CFBundleSupportedPlatforms": ["MacOSX"],
            ],
            to: resourcesURL.appendingPathComponent("Info.plist", isDirectory: false)
        )

        try fileManager.createSymbolicLink(
            atPath: frameworkURL.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A"
        )
        try fileManager.createSymbolicLink(
            atPath: frameworkURL.appendingPathComponent(pluginName).path,
            withDestinationPath: "Versions/Current/\(pluginName)"
        )
        try fileManager.createSymbolicLink(
            atPath: frameworkURL.appendingPathComponent("Resources").path,
            withDestinationPath: "Versions/Current/Resources"
        )

        return Output(bundleURL: bundleURL, executableURL: executableURL)
    }

    private func writePropertyList(_ value: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }
}
