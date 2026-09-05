import ArgumentParser
import Foundation

struct QueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query plugin data with filters."
    )

    @Argument(help: "Plugin name to query (e.g., networking, analytics, logging).")
    var plugin: String

    @Option(name: .long, help: "Session ID to query. Defaults to the current active session.")
    var session: String?

    @Option(name: .long, help: "Filter by URL substring (networking plugin).")
    var url: String?

    @Option(name: .long, help: "Filter by HTTP method (networking plugin).")
    var method: String?

    @Option(name: .long, help: "Filter by HTTP status code (networking plugin).")
    var status: Int?

    @Option(name: .long, help: "Filter by event name (analytics plugin).")
    var event: String?

    @Option(name: .long, help: "Filter by log level (logging plugin).")
    var level: String?

    @Option(name: .long, help: "Only show entries from the last duration (e.g., 5m, 1h, 30s).")
    var last: String?

    @Option(name: .long, help: "Maximum number of results.")
    var limit: Int = 50

    @Option(name: .long, help: "Output format: json (default, one JSON object per line) or compact.")
    var format: QueryOutputFormat = .json

    func validate() throws {
        guard limit > 0 else {
            throw ValidationError("--limit must be a positive integer.")
        }
        if let last {
            guard parseDuration(last) != nil else {
                throw ValidationError("Invalid duration '\(last)'. Use format like 5m, 1h, 30s, or 2d.")
            }
        }
    }

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)
        let fileURL = sessionURL.appendingPathComponent("\(plugin).jsonl")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EchoCLIError.pluginNotFound(plugin)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let allLines = content.split(separator: "\n", omittingEmptySubsequences: true)

        let cutoffDate = parseDuration(last)

        let iso8601 = ISO8601DateFormatter()
        var results: [[String: Any]] = []
        for line in allLines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Time filter
            if let cutoff = cutoffDate,
               let ts = obj["timestamp"] as? String,
               let date = iso8601.date(from: ts),
               date < cutoff {
                continue
            }

            let entryData = obj["data"]

            // Plugin-specific filters
            if let urlFilter = url {
                guard matchesStringField(entryData, key: "url", substring: urlFilter) else { continue }
            }
            if let methodFilter = method {
                guard matchesExactField(entryData, key: "method", value: methodFilter.uppercased()) ||
                      matchesExactField(entryData, key: "httpMethod", value: methodFilter.uppercased()) else { continue }
            }
            if let statusFilter = status {
                guard matchesIntField(entryData, key: "status_code", value: statusFilter) ||
                      matchesIntField(entryData, key: "statusCode", value: statusFilter) else { continue }
            }
            if let eventFilter = event {
                let matchesFlat = matchesExactField(entryData, key: "event", value: eventFilter) ||
                    matchesExactField(entryData, key: "event_name", value: eventFilter)
                let matchesColumnItems = matchesColumnItem(entryData, value: eventFilter)
                guard matchesFlat || matchesColumnItems else { continue }
            }
            if let levelFilter = level {
                guard matchesExactField(entryData, key: "level", value: levelFilter) ||
                      matchesExactField(entryData, key: "log_level", value: levelFilter) else { continue }
            }

            results.append(obj)

            if results.count >= limit { break }
        }

        if results.isEmpty {
            print("No matching entries found.")
            return
        }

        switch format {
        case .json:
            for result in results {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(data: data, encoding: .utf8)!)
            }
        case .compact:
            for result in results {
                let ts = (result["timestamp"] as? String) ?? ""
                let pluginID = (result["plugin_id"] as? String) ?? plugin
                let dataSummary = summarizeData(result["data"])
                print("[\(ts)] [\(pluginID)] \(dataSummary)")
            }
        }

        if results.count == limit {
            FileHandle.standardError.write("(showing first \(limit) results, use --limit to see more)\n".data(using: .utf8)!)
        }
    }

    // MARK: - Private Helpers

    private func parseDuration(_ duration: String?) -> Date? {
        guard let duration, !duration.isEmpty else { return nil }

        let digits = duration.prefix(while: { $0.isNumber || $0 == "." })
        guard let value = Double(digits) else { return nil }
        let unit = String(duration.dropFirst(digits.count))

        let seconds: TimeInterval
        switch unit {
        case "s": seconds = value
        case "m": seconds = value * 60
        case "h": seconds = value * 3600
        case "d": seconds = value * 86400
        default: return nil
        }

        return Date().addingTimeInterval(-seconds)
    }

    private func matchesStringField(_ data: Any?, key: String, substring: String) -> Bool {
        guard let dict = data as? [String: Any],
              let value = dict[key] as? String else { return false }
        return value.range(of: substring, options: .caseInsensitive) != nil
    }

    private func matchesExactField(_ data: Any?, key: String, value: String) -> Bool {
        guard let dict = data as? [String: Any],
              let fieldValue = dict[key] as? String else { return false }
        return fieldValue.caseInsensitiveCompare(value) == .orderedSame
    }

    private func matchesIntField(_ data: Any?, key: String, value: Int) -> Bool {
        guard let dict = data as? [String: Any] else { return false }
        if let intValue = dict[key] as? Int { return intValue == value }
        if let doubleValue = dict[key] as? Double { return Int(doubleValue) == value }
        return false
    }

    private func matchesColumnItem(_ data: Any?, value: String) -> Bool {
        guard let dict = data as? [String: Any],
              let columns = dict["columnItems"] as? [[String: Any]] else { return false }
        return columns.contains { item in
            guard let itemValue = item["value"] as? String else { return false }
            return itemValue.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    private func summarizeData(_ data: Any?) -> String {
        guard let dict = data as? [String: Any] else {
            return String(describing: data ?? "null")
        }
        let parts = dict.sorted(by: { $0.key < $1.key }).prefix(4).map { "\($0.key)=\($0.value)" }
        let suffix = dict.count > 4 ? " ..." : ""
        return parts.joined(separator: " ") + suffix
    }
}

enum QueryOutputFormat: String, ExpressibleByArgument {
    case json
    case compact
}
