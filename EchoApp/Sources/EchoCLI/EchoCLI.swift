import ArgumentParser
import Foundation

@main
struct EchoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "echoapp",
        abstract: "Inspect debug data captured by EchoApp from connected iOS/Android devices.",
        version: cliVersion,
        subcommands: [
            StatusCommand.self,
            SessionsCommand.self,
            TailCommand.self,
            QueryCommand.self,
            ConnectCommand.self,
            ClearCommand.self,
            PluginsCommand.self,
            FixtureCommand.self,
            DebugCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}

// MARK: - Shared Helpers

enum EchoCLIError: Error, CustomStringConvertible {
    case noActiveSession
    case sessionNotFound(String)
    case pluginNotFound(String)

    var description: String {
        switch self {
        case .noActiveSession:
            return "No active EchoApp session. Connect a device in EchoApp.app first."
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .pluginNotFound(let name):
            return "No data for plugin: \(name)"
        }
    }
}

enum SessionDirectory {
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["ECHO_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-sessions", isDirectory: true)
    }()

    /// Well-known directory where CLI sessions register themselves so EchoApp.app can discover them.
    static let registryURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("echo-cli-registry", isDirectory: true)

    static func currentSessionURL() -> URL? {
        let currentURL = baseURL.appendingPathComponent("current")
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return nil }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: currentURL.path) else {
            return nil
        }
        // Resolve relative symlink
        if destination.hasPrefix("./") || !destination.hasPrefix("/") {
            return baseURL.appendingPathComponent(destination).standardized
        }
        return URL(fileURLWithPath: destination)
    }

    static func sessionURL(for sessionID: String) -> URL {
        baseURL.appendingPathComponent(sessionID, isDirectory: true)
    }

    static func resolveSessionURL(sessionID: String?) throws -> URL {
        if let sessionID {
            let url = sessionURL(for: sessionID)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EchoCLIError.sessionNotFound(sessionID)
            }
            return url
        }
        guard let url = currentSessionURL() else {
            throw EchoCLIError.noActiveSession
        }
        return url
    }

    static func readMetadata(at sessionDir: URL) -> SessionMetadataDTO? {
        let url = sessionDir.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionMetadataDTO.self, from: data)
    }

    static func listAllSessions() -> [(url: URL, metadata: SessionMetadataDTO)] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> (URL, SessionMetadataDTO)? in
            guard url.lastPathComponent != "current" else { return nil }
            guard let metadata = readMetadata(at: url) else { return nil }
            return (url, metadata)
        }.sorted { $0.1.startedAt > $1.1.startedAt }
    }
}

/// Registry entry written by `echoapp connect` and read by `echoapp debugmenu`
/// to dispatch mutations to the right local CLI server. Both ends share this
/// type so a field rename can't silently break decoding against existing files
/// (the previous shape was an untyped `[String: String]` dict, which would
/// drop every entry the moment a non-string field was added on the writer side).
struct SessionRegistryEntry: Codable {
    let pid: Int32
    let port: Int
    let sessionDir: String
}

struct SessionMetadataDTO: Codable {
    let id: String
    let deviceName: String
    let deviceType: String
    let startedAt: Date
    let endedAt: Date?
    let plugins: [String]
    let pluginDisplayNames: [String: String]?
    /// Plugin IDs the connected client advertises support for, sourced from
    /// the `ClientInfoPayload` handshake. Distinct from `plugins`, which only
    /// lists plugins that have actually sent data this session. `nil` when
    /// the handshake hasn't arrived yet or the session predates this field.
    let clientPluginIDs: [String]?
}

// MARK: - Version

/// Resolves the CLI version from the embedded Version.plist resource.
/// The release workflow updates CFBundleShortVersionString before building.
/// Falls back to "dev" for local/development builds.
private let cliVersion: String = {
    guard let url = Bundle.module.url(forResource: "Version", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let version = plist["CFBundleShortVersionString"] as? String,
          version != "dev", !version.isEmpty else {
        return "dev"
    }
    return version
}()
