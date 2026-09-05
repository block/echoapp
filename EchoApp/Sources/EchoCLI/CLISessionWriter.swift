import EchoConnection
import Foundation

// MARK: - CLISessionWriter

final class CLISessionWriter {
    private let baseURL: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "echoapp.writer")
    private var currentSessionID: String?
    private var currentSessionDir: URL?
    private var fileHandles: [String: FileHandle] = [:]
    private var knownPlugins: Set<String> = []
    private var deviceName: String?
    private var deviceType: String?
    private var startedAt: Date?
    private var clientPluginIDs: [String]?

    private static let sessionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    var sessionPath: String? {
        queue.sync { currentSessionDir?.path }
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func startSession(deviceName: String, deviceType: String) throws -> String {
        try queue.sync {
            let timestamp = Self.sessionDateFormatter.string(from: Date())
            let safeName = deviceName
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
            let sessionID = "\(timestamp)_\(safeName)"

            let sessionDir = baseURL.appendingPathComponent(sessionID, isDirectory: true)
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

            // Write session.json
            let now = Date()
            let metadata = SessionMetadataDTO(
                id: sessionID,
                deviceName: deviceName,
                deviceType: deviceType,
                startedAt: now,
                endedAt: nil,
                plugins: [],
                pluginDisplayNames: nil,
                clientPluginIDs: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metadata)
            try data.write(to: sessionDir.appendingPathComponent("session.json"))

            // Update current symlink
            let symlinkPath = baseURL.appendingPathComponent("current").path
            try? fileManager.removeItem(atPath: symlinkPath)
            try? fileManager.createSymbolicLink(
                atPath: symlinkPath,
                withDestinationPath: "./\(sessionID)"
            )

            currentSessionID = sessionID
            currentSessionDir = sessionDir
            self.deviceName = deviceName
            self.deviceType = deviceType
            self.startedAt = now
            knownPlugins = []
            clientPluginIDs = nil

            return sessionID
        }
    }

    /// Records the client's `ClientInfoPayload.client_plugin_ids` and rewrites
    /// session.json so `echoapp debugmenu` (and other plugin-aware commands)
    /// can detect when the connected device doesn't implement a plugin
    /// vs. simply hasn't sent data yet.
    func updateClientPluginIDs(_ ids: [String]) {
        queue.sync {
            clientPluginIDs = ids
            writeMetadataLocked(endedAt: nil)
        }
    }

    private func writeMetadataLocked(endedAt: Date?) {
        guard let sessionDir = currentSessionDir else { return }
        let sortedPlugins = Array(knownPlugins).sorted()
        let catalog = PluginCatalog.scan()
        let displayNames = catalog.displayNameMap(for: sortedPlugins)
        let metadata = SessionMetadataDTO(
            id: currentSessionID ?? "",
            deviceName: deviceName ?? "",
            deviceType: deviceType ?? "unknown",
            startedAt: startedAt ?? Date(),
            endedAt: endedAt,
            plugins: sortedPlugins,
            pluginDisplayNames: displayNames.isEmpty ? nil : displayNames,
            clientPluginIDs: clientPluginIDs
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: sessionDir.appendingPathComponent("session.json"))
        }
    }

    func clear() {
        queue.sync {
            guard let sessionDir = currentSessionDir else { return }

            // Close all file handles
            for (_, handle) in fileHandles {
                try? handle.close()
            }
            fileHandles.removeAll()
            knownPlugins.removeAll()

            // Delete all .jsonl files
            let contents = try? fileManager.contentsOfDirectory(
                at: sessionDir,
                includingPropertiesForKeys: nil
            )
            for file in contents ?? [] {
                if file.pathExtension == "jsonl" {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }

    func endSession() {
        queue.sync {
            guard currentSessionDir != nil else { return }

            for (_, handle) in fileHandles {
                try? handle.close()
            }
            fileHandles.removeAll()

            writeMetadataLocked(endedAt: Date())

            // Remove current symlink
            let symlinkURL = baseURL.appendingPathComponent("current")
            try? fileManager.removeItem(at: symlinkURL)

            currentSessionID = nil
            currentSessionDir = nil
        }
    }

    func append(payload: PluginPayload) throws {
        try queue.sync {
            guard let sessionDir = currentSessionDir else { return }

            let pluginID = Self.sanitizePluginID(payload.pluginID)
            knownPlugins.insert(pluginID)

            let fileURL = sessionDir.appendingPathComponent("\(pluginID).jsonl")

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
            handle.seekToEndOfFile()
            handle.write(line)
        }
    }

    static func sanitizePluginID(_ pluginID: String) -> String {
        PluginID.sanitize(pluginID)
    }

    private func fileHandle(for url: URL) throws -> FileHandle {
        let key = url.lastPathComponent
        if let existing = fileHandles[key] { return existing }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        fileHandles[key] = handle
        return handle
    }
}
