import EchoConnection
import Foundation

/// Writes plugin payloads to append-only JSONL files organized by session.
///
/// Directory structure:
///   $TMPDIR/echo-sessions/current -> ./2025-03-31T12-00-00_iPhone-15/
///   $TMPDIR/echo-sessions/2025-03-31T12-00-00_iPhone-15/
///     session.json
///     networking.jsonl
///     analytics.jsonl
///     ...
actor SessionFileCache {

    // MARK: - Types

    struct SessionMetadata: Codable {
        let id: String
        let deviceName: String
        let deviceType: String
        let startedAt: Date
        var endedAt: Date?
        var plugins: [String]
    }

    // MARK: - Properties

    private let baseURL: URL
    private let maxSessions: Int
    private let fileManager: FileManager
    private var currentSessionID: String?
    private var currentSessionURL: URL?
    private var fileHandles: [String: FileHandle] = [:]
    private var knownPlugins: Set<String> = []

    private static let sessionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Initialization

    init(baseURL: URL? = nil, maxSessions: Int = 10, fileManager: FileManager = .default) {
        self.baseURL = baseURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("echo-sessions", isDirectory: true)
        self.maxSessions = maxSessions
        self.fileManager = fileManager
    }

    // MARK: - Session Lifecycle

    /// Start a new session for a connected device.
    func startSession(deviceName: String, deviceType: String) throws -> String {
        try endSession()

        let timestamp = Self.sessionDateFormatter.string(from: Date())
        let safeName = deviceName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let sessionID = "\(timestamp)_\(safeName)"

        let sessionDir = baseURL.appendingPathComponent(sessionID, isDirectory: true)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let metadata = SessionMetadata(
            id: sessionID,
            deviceName: deviceName,
            deviceType: deviceType,
            startedAt: Date(),
            endedAt: nil,
            plugins: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: sessionDir.appendingPathComponent("session.json"))

        updateCurrentSymlink(to: sessionID)

        currentSessionID = sessionID
        currentSessionURL = sessionDir
        knownPlugins = []

        purgeOldSessions()

        return sessionID
    }

    /// End the current session, updating metadata and closing file handles.
    func endSession() throws {
        guard let sessionURL = currentSessionURL else { return }

        for (_, handle) in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()

        let metadataURL = sessionURL.appendingPathComponent("session.json")
        if fileManager.fileExists(atPath: metadataURL.path),
           let metadataData = try? Data(contentsOf: metadataURL),
           var metadata = try? JSONDecoder.iso8601Decoder().decode(SessionMetadata.self, from: metadataData) {
            metadata.endedAt = Date()
            metadata.plugins = Array(knownPlugins).sorted()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let updated = try encoder.encode(metadata)
            try updated.write(to: metadataURL)
        }

        removeCurrentSymlink()

        currentSessionID = nil
        currentSessionURL = nil
        knownPlugins = []
    }

    // MARK: - Writing Data

    /// Append a plugin payload as a JSONL line to the appropriate file.
    func append(payload: PluginPayload) throws {
        guard let sessionURL = currentSessionURL else { return }

        let pluginID = Self.sanitizePluginID(payload.pluginID)
        knownPlugins.insert(pluginID)

        let fileURL = sessionURL.appendingPathComponent("\(pluginID).jsonl")

        let timestamp = Self.iso8601Formatter.string(from: Date())
        var jsonObject: [String: Any] = ["timestamp": timestamp, "plugin_id": pluginID]
        if let command = payload.command {
            jsonObject["command"] = command
        }

        if let parsed = try? JSONSerialization.jsonObject(with: payload.data) {
            jsonObject["data"] = parsed
        } else if let stringValue = String(data: payload.data, encoding: .utf8) {
            jsonObject["data"] = stringValue
        } else {
            jsonObject["data"] = payload.data.base64EncodedString()
        }

        let lineData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        var line = lineData
        line.append(contentsOf: "\n".utf8)

        let handle = try fileHandle(for: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    // MARK: - Reading Data

    /// List all sessions, sorted newest first.
    func listSessions() -> [SessionMetadata] {
        guard fileManager.fileExists(atPath: baseURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let entries = try fileManager.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return entries.compactMap { url -> SessionMetadata? in
                guard url.lastPathComponent != "current" else { return nil }
                let metadataURL = url.appendingPathComponent("session.json")
                guard let data = try? Data(contentsOf: metadataURL) else { return nil }
                return try? decoder.decode(SessionMetadata.self, from: data)
            }.sorted { $0.startedAt > $1.startedAt }
        } catch {
            return []
        }
    }

    /// Read JSONL lines from a plugin file in the current (or specified) session.
    func readLines(plugin: String, sessionID: String? = nil) throws -> [Data] {
        let sessionDir: URL
        if let sessionID {
            sessionDir = baseURL.appendingPathComponent(sessionID, isDirectory: true)
        } else if let currentSessionURL {
            sessionDir = currentSessionURL
        } else {
            return []
        }

        let pluginID = Self.sanitizePluginID(plugin)
        let fileURL = sessionDir.appendingPathComponent("\(pluginID).jsonl")
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let content = try Data(contentsOf: fileURL)
        guard let string = String(data: content, encoding: .utf8) else { return [] }

        return string.split(separator: "\n", omittingEmptySubsequences: true)
            .map { Data($0.utf8) }
    }

    /// Get the path to the current session directory (if any).
    var currentSessionPath: String? {
        currentSessionURL?.path
    }

    /// Get the current session ID (if any).
    var activeSessionID: String? {
        currentSessionID
    }

    // MARK: - Private Helpers

    private func fileHandle(for url: URL) throws -> FileHandle {
        let key = url.lastPathComponent
        if let existing = fileHandles[key] {
            return existing
        }

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        fileHandles[key] = handle
        return handle
    }

    private func updateCurrentSymlink(to sessionID: String) {
        let symlinkPath = baseURL.appendingPathComponent("current").path
        try? fileManager.removeItem(atPath: symlinkPath)
        try? fileManager.createSymbolicLink(
            atPath: symlinkPath,
            withDestinationPath: "./\(sessionID)"
        )
    }

    private func removeCurrentSymlink() {
        let symlinkURL = baseURL.appendingPathComponent("current")
        try? fileManager.removeItem(at: symlinkURL)
    }

    private func purgeOldSessions() {
        let sessions = listSessions()
        guard sessions.count > maxSessions else { return }
        let toDelete = sessions.suffix(from: maxSessions)
        for session in toDelete {
            let sessionDir = baseURL.appendingPathComponent(session.id, isDirectory: true)
            try? fileManager.removeItem(at: sessionDir)
        }
    }

    static func sanitizePluginID(_ pluginID: String) -> String {
        let components = pluginID.split(separator: ".")
        if components.count > 1 {
            return String(components.last!)
        }
        return pluginID
    }
}

// MARK: - JSONDecoder Helpers

private extension JSONDecoder {
    static func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
