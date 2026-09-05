import ComposableArchitecture
import EchoMCP
import Foundation
import MCP

// MARK: - ExchangeListResult

public struct ExchangeListResult {
    public let total: Int
    public let exchanges: [[String: Any]]
}

// MARK: - NetworkingMCPToolProvider

/// Exposes Networking plugin data (HTTP exchanges) as MCP tools.
public final class NetworkingMCPToolProvider: MCPToolProvider {

    private let store: Store<AppState, AppAction>
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    public init(store: Store<AppState, AppAction>) {
        self.store = store
    }

    // MARK: - MCPToolProvider

    public var mcpTools: [Tool] {
        [
            Tool(
                name: "list_exchanges",
                description: "Lists captured network packets with optional filters (url, method, status_code, last_seconds, since, limit, offset, device_id).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object(["type": .string("string"), "description": .string("Filter by URL substring")]),
                        "method": .object(["type": .string("string"), "description": .string("HTTP method filter")]),
                        "status_code": .object(["type": .string("integer"), "description": .string("HTTP status code filter")]),
                        "last_seconds": .object(["type": .string("integer"), "description": .string("Only packets from last N seconds")]),
                        "since": .object(["type": .string("string"), "description": .string("ISO8601 timestamp lower bound")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max results (default 50)")]),
                        "offset": .object(["type": .string("integer"), "description": .string("Pagination offset (default 0)")]),
                        "device_id": .object(["type": .string("string"), "description": .string("Device session ID filter")]),
                    ])
                ])
            ),
            Tool(
                name: "get_exchange",
                description: "Returns full details of one packet: request headers, request body, response headers, response body, status code.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["id": .object(["type": .string("string"), "description": .string("Exchange UUID")])]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "search_exchanges",
                description: "Searches captured packets by URL substring.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string"), "description": .string("URL substring")]),
                        "last_seconds": .object(["type": .string("integer"), "description": .string("Limit to last N seconds")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max results (default 50)")]),
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(name: "clear_exchanges", description: "Clears all captured network packets.", inputSchema: .object(["type": .string("object")])),
        ]
    }

    public func handle(toolName: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        switch toolName {
        case "list_exchanges":
            return try await handleListExchanges(arguments: arguments)
        case "search_exchanges":
            let query = arguments?["query"]?.stringValue ?? ""
            let lastSeconds = arguments?["last_seconds"]?.intValue
            let limit = arguments?["limit"]?.intValue ?? 50
            let result = await MainActor.run {
                self.listExchanges(urlFilter: query, method: nil, statusCode: nil, lastSeconds: lastSeconds, since: nil, limit: limit, offset: 0)
            }
            let output: [String: Any] = ["total": result.total, "exchanges": result.exchanges]
            let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
            return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
        case "get_exchange":
            guard let idStr = arguments?["id"]?.stringValue, let uuid = UUID(uuidString: idStr) else {
                return .init(content: [.text("Invalid or missing 'id' parameter.")], isError: true)
            }
            let detail = await MainActor.run { self.getExchange(id: uuid) }
            guard let detail else { return .init(content: [.text("Exchange not found: \(idStr)")], isError: false) }
            let json = try JSONSerialization.data(withJSONObject: detail, options: [.prettyPrinted])
            return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
        case "clear_exchanges":
            await MainActor.run { self.clearExchanges() }
            return .init(content: [.text("Exchanges cleared.")], isError: false)
        default:
            return .init(content: [.text("Unknown tool: \(toolName)")], isError: true)
        }
    }

    // MARK: - Internal helpers (exposed for testing)

    @MainActor
    public func listExchanges(
        urlFilter: String?,
        method: String?,
        statusCode: Int?,
        lastSeconds: Int?,
        since: Date?,
        limit: Int,
        offset: Int
    ) -> ExchangeListResult {
        var filtered = store.withState { $0.exchanges }
        if let urlFilter { filtered = filtered.filter { $0.request.url.absoluteString.contains(urlFilter) } }
        if let method { filtered = filtered.filter { $0.request.httpMethod.uppercased() == method.uppercased() } }
        if let statusCode { filtered = filtered.filter { $0.response?.statusCode == statusCode } }
        if let lastSeconds {
            let cutoff = Date().addingTimeInterval(-Double(lastSeconds))
            filtered = filtered.filter { $0.request.timestamp >= cutoff }
        }
        if let since { filtered = filtered.filter { $0.request.timestamp >= since } }
        let total = filtered.count
        let page = Array(filtered.dropFirst(offset).prefix(limit))
        return ExchangeListResult(total: total, exchanges: page.map { $0.mcpSummary() })
    }

    @MainActor
    public func getExchange(id: UUID) -> [String: Any]? {
        store.withState { $0.exchanges.first { $0.id == id } }?.mcpDetail()
    }

    @MainActor
    public func clearExchanges() {
        store.send(.exchange(.clearExchanges))
    }

    // MARK: - Private

    private func handleListExchanges(arguments: [String: Value]?) async throws -> CallTool.Result {
        let urlFilter = arguments?["url"]?.stringValue
        let method = arguments?["method"]?.stringValue
        let statusCode = arguments?["status_code"]?.intValue
        let lastSeconds = arguments?["last_seconds"]?.intValue
        let limit = arguments?["limit"]?.intValue ?? 50
        let offset = arguments?["offset"]?.intValue ?? 0
        let sinceDate = arguments?["since"]?.stringValue.flatMap { Self.iso8601.date(from: $0) }
        let result = await MainActor.run {
            self.listExchanges(urlFilter: urlFilter, method: method, statusCode: statusCode, lastSeconds: lastSeconds, since: sinceDate, limit: limit, offset: offset)
        }
        let output: [String: Any] = ["total": result.total, "exchanges": result.exchanges]
        let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
        return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
    }
}
