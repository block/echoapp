import Foundation
import SwiftUI
import System
import UniformTypeIdentifiers

struct PluginDragAndDropView: View {
    @Binding var isInstalling: Bool

    var body: some View {
        VStack(spacing: 20) {
            if isInstalling {
                Text("Installing plugins")
                    .font(.title2)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else {
                Image(systemName: "arrow.down.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.secondary)
                Text("Drop now to to install plugin(s).")
                    .font(.title2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10) // Adjust cornerRadius for roundness
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [4, 8]))
                .foregroundColor(.secondary)
                .background(Color(white: 0.0, opacity: 0.04))
                .cornerRadius(10)
        )
        .padding(40)

    }
}


extension PluginsSettingsView {

    internal func handleDrop(providers: [NSItemProvider]) async {
        isInstalling = true

        let providers = Set(providers)
        let zipFiles = providers.filter { $0.hasItemConformingToTypeIdentifier("public.zip-archive") }
        let directories = providers.subtracting(zipFiles)
        var installedPlugins = 0
        var failedPlugins = 0

        guard directories.count > 0 || zipFiles.count > 0 else {
            isInstalling = false
            installFailureMessage = "No supported plugin formats found"
            return
        }

        // Copy the directories
        let (installedDirectoryPlugins, failedDirectoryPlugins) = await installPluginFromDirectory(providers: directories)
        installedPlugins += installedDirectoryPlugins
        failedPlugins += failedDirectoryPlugins

        // Unzip and install plugins from any avaialble echoplugin bundles
        let (installedZipPlugins, failedZipPlugins) = await installPluginFromZip(providers: zipFiles)
        installedPlugins += installedZipPlugins
        failedPlugins += failedZipPlugins

        // Finalize install
        if installedPlugins > 0 && failedPlugins == 0 {
            installSuccessMessage = "Installed \(installedPlugins) plugins"
        } else if installedPlugins > 0 {
            installSuccessMessage = "Installed \(installedPlugins) plugins but \(failedPlugins) plugins failed to install"
        } else {
            installFailureMessage = "Unable to install any plugins from \(providers.count) provided items"
        }

        isInstalling = false
        isAlertShown = true
    }

    private func installPluginFromDirectory(providers: Set<NSItemProvider>) async -> (installed: Int, failed: Int) {
        var installedPlugins = 0
        var failedPlugins = 0

        for directory in providers {
            do {
                let item = try await directory.loadItem(forTypeIdentifier: "public.data")
                guard let url = item as? URL else {
                    failedPlugins += 1
                    continue
                }

                try installPlugin(at: url)
                installedPlugins += 1

            } catch {
                failedPlugins += 1
            }
        }

        return (installed: installedPlugins, failed: failedPlugins)
    }

    private func installPluginFromZip(providers: Set<NSItemProvider>) async -> (installed: Int, failed: Int) {
        var installedPlugins = 0
        var failedPlugins = 0

        for archive in providers {
            do {
                guard let zipURL = try await archive.loadItem(forTypeIdentifier: "public.zip-archive") as? URL else {
                    failedPlugins += 1
                    continue
                }

                installedPlugins += try extractZip(at: zipURL)
            } catch {
                failedPlugins += 1
            }
        }

        return (installed: installedPlugins, failed: failedPlugins)
    }

    private func installPlugin(at sourceURL: URL) throws {
        let installationPath = pluginLocationProvider.applicationSupport()
        let pluginName = sourceURL.lastPathComponent
        AnalyticsProvider.shared.trackPluginInstalled(pluginId: pluginName)
        let pluginInstallURL = installationPath.appendingPathComponent(pluginName)
        try? fileManager.removeItem(at: pluginInstallURL)
        try fileManager.copyItem(at: sourceURL, to: pluginInstallURL)
    }

    private func extractZip(at sourceURL: URL) throws -> Int {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory() + sourceURL.lastPathComponent)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", sourceURL.path, "-d", tempDirectory.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw InstallError.unzipFailed
        }

        let contents = try fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )

        let echoPluginBundles = contents.filter { $0.pathExtension == "echoplugin" }
        guard !echoPluginBundles.isEmpty else {
            throw InstallError.noPluginBundlesInZip
        }

        var installedPlugins = 0
        for bundle in echoPluginBundles {
            try installPlugin(at: bundle)
            installedPlugins += 1
        }

        return installedPlugins
    }
}

enum InstallError: Error {
    case noPluginBundlesInZip
    case unzipFailed
}

extension NSItemProvider: @retroactive @unchecked Sendable { }
