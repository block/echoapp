import Foundation

// MARK: - InstalledPlugin

struct InstalledPlugin {
    let sanitizedID: String
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let version: String?
    let pluginDescription: String?
    let agentsMarkdown: String?
}

// MARK: - PluginCatalog

struct PluginCatalog {
    let plugins: [InstalledPlugin]

    static func scan() -> PluginCatalog {
        let fileManager = FileManager.default
        var allEntries: [URL] = []

        // Scan ~/Library/Application Support/Echo/Plugins/
        if let pluginsDir = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Echo")
            .appendingPathComponent("Plugins"),
           fileManager.fileExists(atPath: pluginsDir.path) {
            if let entries = try? fileManager.contentsOfDirectory(
                at: pluginsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                allEntries.append(contentsOf: entries.filter { $0.pathExtension == "echoplugin" })
            }
        }

        // Scan EchoApp.app/Contents/Plugins/
        let appPaths = [
            "/Applications/EchoApp.app",
            NSHomeDirectory() + "/Applications/EchoApp.app",
        ]
        for appPath in appPaths {
            let appPluginsDir = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Plugins")
            if fileManager.fileExists(atPath: appPluginsDir.path),
               let entries = try? fileManager.contentsOfDirectory(
                at: appPluginsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                allEntries.append(contentsOf: entries.filter { $0.pathExtension == "echoplugin" })
            }
        }

        let plugins = allEntries.compactMap { parsePlugin(at: $0) }
        return PluginCatalog(plugins: plugins)
    }

    /// Resolve a plugin by sanitized ID, bundle ID, or display name.
    func resolve(_ query: String) -> InstalledPlugin? {
        let lowered = query.lowercased()
        return plugins.first(where: { $0.sanitizedID.lowercased() == lowered })
            ?? plugins.first(where: { $0.bundleIdentifier.lowercased() == lowered })
            ?? plugins.first(where: { $0.displayName.lowercased() == lowered })
            ?? (lowered.count >= 2 ? plugins.first(where: { $0.displayName.lowercased().contains(lowered) }) : nil)
    }

    /// Build a display name map for known sanitized IDs.
    func displayNameMap(for sanitizedIDs: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for id in sanitizedIDs {
            if let plugin = plugins.first(where: { $0.sanitizedID == id }) {
                map[id] = plugin.displayName
            }
        }
        return map
    }

    // MARK: - Private

    private static func parsePlugin(at url: URL) -> InstalledPlugin? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }

        let bundleIdentifier = plist["CFBundleIdentifier"] as? String ?? ""
        let bundleName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let version = plist["CFBundleShortVersionString"] as? String

        // Try reading plugin metadata plist for canonical ID and display name
        let pluginMetadata = readPluginMetadata(in: url)
        let sanitizedID = pluginMetadata?.sanitizedID ?? derivePluginID(from: bundleName)
        let displayName = pluginMetadata?.displayName ?? deriveDisplayName(from: bundleName)
        let pluginDescription = pluginMetadata?.pluginDescription

        // Find AGENTS.md files recursively in the bundle
        let agentsMarkdown = findAgentsMarkdown(in: url)

        return InstalledPlugin(
            sanitizedID: sanitizedID,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: url,
            version: version,
            pluginDescription: pluginDescription,
            agentsMarkdown: agentsMarkdown
        )
    }

    /// Derive a JSONL-compatible plugin ID from a desktop plugin bundle name.
    /// "KeyValueStoreDesktopPlugin" -> "keyvaluestore"
    /// "FeatureFlagsDesktopPlugin" -> "featureflags"
    private static func derivePluginID(from bundleName: String) -> String {
        var name = bundleName
        if name.hasSuffix("DesktopPlugins") {
            name = String(name.dropLast("DesktopPlugins".count))
        } else if name.hasSuffix("DesktopPlugin") {
            name = String(name.dropLast("DesktopPlugin".count))
        }
        return name.lowercased()
    }

    /// Derive a human-readable display name from a bundle name.
    /// "KeyValueStoreDesktopPlugin" -> "Key Value Store"
    /// "FeatureFlagsDesktopPlugin" -> "Feature Flags"
    private static func deriveDisplayName(from bundleName: String) -> String {
        var name = bundleName
        if name.hasSuffix("DesktopPlugins") {
            name = String(name.dropLast("DesktopPlugins".count))
        } else if name.hasSuffix("DesktopPlugin") {
            name = String(name.dropLast("DesktopPlugin".count))
        }
        // Insert spaces at camelCase boundaries, handling acronyms
        var result = ""
        let chars = Array(name)
        for (i, char) in chars.enumerated() {
            if i > 0 && char.isUppercase {
                let prevChar = chars[i - 1]
                if prevChar.isLowercase {
                    // camelCase boundary: "userJ" -> "user J"
                    result.append(" ")
                } else if prevChar.isUppercase && i + 1 < chars.count && chars[i + 1].isLowercase {
                    // Acronym end: "HTTPClient" -> "HTTP Client" (at the 'C')
                    result.append(" ")
                }
            }
            result.append(char)
        }
        return result
    }

    private struct PluginMetadataInfo {
        let sanitizedID: String
        let displayName: String
        let pluginDescription: String?
    }

    private static func readPluginMetadata(in bundleURL: URL) -> PluginMetadataInfo? {
        // Search for PluginInfo.plist in the bundle
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "PluginInfo.plist" else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }
            guard let displayName = plist["displayName"] as? String else { continue }
            let pluginID: String
            if let id = plist["id"] as? String {
                pluginID = PluginID.sanitize(id)
            } else {
                continue
            }
            let pluginDescription = plist["description"] as? String
            return PluginMetadataInfo(
                sanitizedID: pluginID,
                displayName: displayName,
                pluginDescription: pluginDescription
            )
        }
        return nil
    }

    private static func findAgentsMarkdown(in directory: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "AGENTS.md" {
                return try? String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        return nil
    }
}
