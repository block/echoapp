import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current EchoApp session status."
    )

    @Option(name: .long, help: "Output format: text or json.")
    var format: OutputFormat = .text

    func run() throws {
        guard let sessionURL = SessionDirectory.currentSessionURL(),
              let metadata = SessionDirectory.readMetadata(at: sessionURL) else {
            if format == .json {
                print("{\"connected\": false}")
            } else {
                print("No active EchoApp session. Connect a device in EchoApp.app first.")
            }
            return
        }

        let iso = ISO8601DateFormatter()

        if format == .json {
            var output: [String: Any] = [
                "connected": true,
                "device_name": metadata.deviceName,
                "device_type": metadata.deviceType,
                "session_id": metadata.id,
                "session_path": sessionURL.path,
                "started_at": iso.string(from: metadata.startedAt),
                "plugins": metadata.plugins,
            ]
            if let endedAt = metadata.endedAt {
                output["ended_at"] = iso.string(from: endedAt)
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Device:  \(metadata.deviceName) (\(metadata.deviceType))")
            print("Session: \(sessionURL.path)")
            print("Plugins: \(metadata.plugins.joined(separator: ", "))")
            print("Since:   \(iso.string(from: metadata.startedAt))")
            if let endedAt = metadata.endedAt {
                print("Ended:   \(iso.string(from: endedAt))")
            }
        }
    }
}

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
}
