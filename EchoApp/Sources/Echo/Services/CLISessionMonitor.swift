import Foundation
import Observation
import os

// MARK: - CLISession

struct CLISession: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let deviceType: String
    let startedAt: Date
    let plugins: [String]
    let sessionPath: String
}

// MARK: - CLISessionMonitor

@MainActor
@Observable
final class CLISessionMonitor {
    private(set) var activeCLISessions: [CLISession] = []

    private let registryURL: URL
    private let logger = Logger(subsystem: "xyz.block.echoapp", category: "CLISessionMonitor")
    private var pollingTask: Task<Void, Never>?

    init(registryURL: URL? = nil) {
        self.registryURL = registryURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("echo-cli-registry", isDirectory: true)
    }

    func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSessions()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        activeCLISessions = []
    }

    // MARK: - Private

    private func refreshSessions() async {
        let sessions = await Task.detached { [registryURL, logger] in
            return CLISessionMonitor.scanRegistry(at: registryURL, logger: logger)
        }.value

        if activeCLISessions != sessions {
            activeCLISessions = sessions
        }
    }

    private nonisolated static func scanRegistry(at registryURL: URL, logger: Logger) -> [CLISession] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return []
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: registryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var sessions: [CLISession] = []
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let info = try? JSONDecoder().decode(CLIRegistryEntry.self, from: data) else {
                continue
            }

            // Verify the process is still running
            guard let pid = Int32(info.pid), kill(pid, 0) == 0 else {
                // Stale entry -- clean it up
                try? fileManager.removeItem(at: entry)
                continue
            }

            let sessionDir = URL(fileURLWithPath: info.sessionDir, isDirectory: true)
            guard let metadata = readMetadata(in: sessionDir) else { continue }

            // Only show sessions that haven't ended
            guard metadata.endedAt == nil else { continue }

            sessions.append(CLISession(
                id: metadata.id,
                deviceName: metadata.deviceName,
                deviceType: metadata.deviceType,
                startedAt: metadata.startedAt,
                plugins: metadata.plugins,
                sessionPath: sessionDir.path
            ))
        }

        // Sort by start time descending for stable ordering
        sessions.sort { $0.startedAt > $1.startedAt }
        return sessions
    }

    private nonisolated static func readMetadata(in sessionDir: URL) -> CLISessionMetadata? {
        let url = sessionDir.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CLISessionMetadata.self, from: data)
    }
}

// MARK: - CLIRegistryEntry

private struct CLIRegistryEntry: Codable {
    let pid: String
    let sessionDir: String
}

// MARK: - CLISessionMetadata

private struct CLISessionMetadata: Codable {
    let id: String
    let deviceName: String
    let deviceType: String
    let startedAt: Date
    let endedAt: Date?
    let plugins: [String]
}
