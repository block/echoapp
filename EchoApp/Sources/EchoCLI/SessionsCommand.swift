import ArgumentParser
import Foundation

struct SessionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List all EchoApp sessions."
    )

    @Option(name: .long, help: "Output format: text or json.")
    var format: OutputFormat = .text

    func run() throws {
        let sessions = SessionDirectory.listAllSessions()
        let currentURL = SessionDirectory.currentSessionURL()

        if sessions.isEmpty {
            if format == .json {
                print("[]")
            } else {
                print("No EchoApp sessions found.")
            }
            return
        }

        if format == .json {
            let iso = ISO8601DateFormatter()
            let output: [[String: Any]] = sessions.map { (url, metadata) in
                var entry: [String: Any] = [
                    "id": metadata.id,
                    "device_name": metadata.deviceName,
                    "device_type": metadata.deviceType,
                    "started_at": iso.string(from: metadata.startedAt),
                    "plugins": metadata.plugins,
                    "active": url.standardized.path == currentURL?.standardized.path,
                ]
                if let endedAt = metadata.endedAt {
                    entry["ended_at"] = iso.string(from: endedAt)
                }
                return entry
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            for (url, metadata) in sessions {
                let isActive = url.standardized.path == currentURL?.standardized.path
                let marker = isActive ? "* " : "  "
                let suffix = isActive ? "  (active)" : ""
                print("\(marker)\(metadata.id)\(suffix)")
            }
        }
    }
}
