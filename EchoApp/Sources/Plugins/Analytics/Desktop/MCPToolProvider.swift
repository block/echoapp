import EchoMCP
import EchoPluginAPI
import Foundation
import MCP

// MARK: - AnalyticsMCPToolProvider

/// Exposes Analytics plugin data (analytics events) as MCP tools.
///
/// Reads from a rowsProvider closure — no mutations, no store actions.
public final class AnalyticsMCPToolProvider: MCPToolProvider {

    private let rowsProvider: @MainActor () -> [EchoTableRow]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public init(rowsProvider: @escaping @MainActor () -> [EchoTableRow]) {
        self.rowsProvider = rowsProvider
    }

    // MARK: - MCPToolProvider

    public var mcpTools: [Tool] {
        [
            Tool(
                name: "list_analytics_events",
                description: "Lists captured analytics events. Returns Time, Source, and Event name. Supports filtering by event name and time window.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "event_name": .object(["type": .string("string"), "description": .string("Filter by exact event name (case-sensitive)")]),
                        "last_seconds": .object(["type": .string("integer"), "description": .string("Only events from the last N seconds")]),
                        "since": .object(["type": .string("string"), "description": .string("ISO8601 timestamp lower bound")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max results (default 50)")]),
                        "offset": .object(["type": .string("integer"), "description": .string("Pagination offset (default 0)")]),
                    ])
                ])
            ),
            Tool(
                name: "get_analytics_events",
                description: "Returns full detail for analytics events including raw JSON payload and properties. Supports filtering by event name and time window.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "event_name": .object(["type": .string("string"), "description": .string("Filter by exact event name")]),
                        "last_seconds": .object(["type": .string("integer"), "description": .string("Only events from the last N seconds")]),
                        "since": .object(["type": .string("string"), "description": .string("ISO8601 timestamp lower bound")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max results (default 100)")]),
                        "offset": .object(["type": .string("integer"), "description": .string("Pagination offset (default 0)")]),
                    ])
                ])
            ),
        ]
    }

    public func handle(toolName: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch toolName {
        case "list_analytics_events":
            return try await handleEvents(arguments: arguments, includeDetail: false)
        case "get_analytics_events":
            return try await handleEvents(arguments: arguments, includeDetail: true)
        default:
            return .init(content: [.text("Unknown tool: \(toolName)")], isError: true)
        }
    }

    // MARK: - Private

    private func handleEvents(arguments: [String: Value]?, includeDetail: Bool) async throws -> CallTool.Result {
        let eventNameFilter = arguments?["event_name"]?.stringValue
        let lastSeconds = arguments?["last_seconds"]?.intValue
        let limit = arguments?["limit"]?.intValue ?? (includeDetail ? 100 : 50)
        let offset = arguments?["offset"]?.intValue ?? 0
        let sinceDate: Date? = arguments?["since"]?.stringValue
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        let rows = await MainActor.run { rowsProvider() }
        var filtered = rows

        if let eventNameFilter {
            filtered = filtered.filter { $0.columnItems["Event"] == eventNameFilter }
        }
        if let lastSeconds {
            let cutoff = Date().addingTimeInterval(-Double(lastSeconds))
            filtered = filtered.filter { row in
                guard let timeStr = row.columnItems["Time"],
                      let date = Self.timeFormatter.date(from: timeStr) else { return true }
                return date >= cutoff
            }
        }
        if let sinceDate {
            filtered = filtered.filter { row in
                guard let timeStr = row.columnItems["Time"],
                      let date = Self.timeFormatter.date(from: timeStr) else { return true }
                return date >= sinceDate
            }
        }

        let total = filtered.count
        let page = Array(filtered.dropFirst(offset).prefix(limit))

        let events: [[String: Any]] = page.map { row in
            if includeDetail {
                return row.columnItems.reduce(into: [:]) { $0[$1.key] = $1.value }
            } else {
                return [
                    "time": row.columnItems["Time"] ?? "",
                    "source": row.columnItems["Source"] ?? "",
                    "event": row.columnItems["Event"] ?? "",
                ]
            }
        }

        let output: [String: Any] = ["total": total, "events": events]
        let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
        return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
    }
}

// MARK: - AnalyticsDesktopPlugin: MCPToolProvider

extension AnalyticsDesktopPlugin: MCPToolProvider {
    public var mcpTools: [Tool] { mcpProvider.mcpTools }

    public func handle(toolName: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        try await mcpProvider.handle(toolName: toolName, arguments: arguments)
    }

    // Lazy provider stored as associated object to avoid per-call allocation
    fileprivate var mcpProvider: AnalyticsMCPToolProvider {
        if let existing = objc_getAssociatedObject(self, &AnalyticsDesktopPlugin.mcpProviderKey) as? AnalyticsMCPToolProvider {
            return existing
        }
        let provider = AnalyticsMCPToolProvider(rowsProvider: { [weak self] in self?.rows ?? [] })
        objc_setAssociatedObject(self, &AnalyticsDesktopPlugin.mcpProviderKey, provider, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return provider
    }

    private static var mcpProviderKey: UInt8 = 0
}
