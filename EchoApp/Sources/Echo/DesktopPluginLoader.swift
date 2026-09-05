import Foundation
import EchoPluginAPI
import os

// MARK: - Framework Plugin Loader

final class FrameworkPluginLoader {

    // MARK: - Private Properties

    private let fileManager: FileManager
    private let pluginLocationProvider: DesktopPluginLocationProvider
    private var frameworksByID: [PluginIdentifier: FrameworkPlugin] = [:]

    // MARK: - Life Cycle

    init(
        fileManager: FileManager = .default,
        pluginLocationProvider: DesktopPluginLocationProvider = .init()
    ) {
        self.fileManager = fileManager
        self.pluginLocationProvider = pluginLocationProvider
    }

    // MARK: - Public Methods

    func loadPluginFrameworks() throws -> some Collection<FrameworkPlugin> {
        // Plugin frameworks are loaded from both the .app bundle and from Application Support
        let appSupportPluginsDirectory = try makeAppSupportPluginsDirectoryIfNeeded()
        let appSupportFrameworks = frameworkPlugins(inDirectory: appSupportPluginsDirectory)

        let appBundlePluginsDirectory = Bundle.main.bundleURL.appending(path: "Contents/Plugins")
        let appBundleFrameworks = frameworkPlugins(inDirectory: appBundlePluginsDirectory)

        let allFrameworks = appSupportFrameworks + appBundleFrameworks
        let frameworksByBundleID = Dictionary(
            allFrameworks.map { ($0.bundleID, $0) },
            uniquingKeysWith: { appSupportFramework, _ in
                // Prefer Application Support frameworks:
                appSupportFramework
            }
        )
        return frameworksByBundleID.values
    }

}

// MARK: -

private extension FrameworkPluginLoader {

    /// Search the `.echoplugin` bundle format for expected frameworks.
    /// The plugin format is defined as:
    ///
    /// ```
    /// MyPlugin.echoplugin
    ///   Contents/
    ///     Info.plist
    ///     MacOS/
    ///       MyPlugin.framework
    /// ```
    private func frameworkPlugins(inDirectory directory: URL) -> [FrameworkPlugin] {
        do {
            let echoPlugins = try fileManager
                .contents(of: directory, withExtension: "echoplugin")

            let frameworkPlugins = echoPlugins
                .map { pluginPath in
                    let frameworkPath = pluginPath
                        .appendingPathComponent("Contents")
                        .appendingPathComponent("MacOS")
                        .appendingPathComponent(pluginPath.deletingPathExtension().lastPathComponent)
                        .appendingPathExtension("framework")
                    return frameworkPath
                }
                .map(FrameworkPlugin.init)

            return frameworkPlugins
        } catch {
            return []
        }
    }

    private func makeAppSupportPluginsDirectoryIfNeeded() throws -> URL {
        let pluginsDirectory = pluginLocationProvider.applicationSupport()
        do {
            try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true, attributes: nil)
            return pluginsDirectory
        } catch {
            Logger.echoLogger(category: "FrameworkPluginLoader")
                .error("Failed to create plugins directory \(pluginsDirectory): \(error)")
            throw PluginLoaderError.failedToCreatePluginsDirectory(pluginsDirectory, error)
        }
    }
}

// MARK: -

extension FileManager {

    func contents(
        of directory: URL,
        withExtension pathExtension: String
    ) throws -> [URL] {
        try contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.pathExtension == pathExtension }
    }

}
