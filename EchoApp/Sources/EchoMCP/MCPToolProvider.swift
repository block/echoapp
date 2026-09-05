import MCP

/// A plugin that exposes MCP tools to Claude (or other MCP clients).
///
/// Conform to this protocol on a `DesktopPlugin` to have MCPServer
/// auto-discover and register your tools at startup.
///
/// MCPServer receives the full loaded-plugin list at `start(plugins:)` and
/// calls `compactMap { $0 as? MCPToolProvider }` — no manual registration needed.
public protocol MCPToolProvider: AnyObject {
    /// The MCP `Tool` definitions this provider exposes.
    /// Called once at server startup to build the tools list.
    var mcpTools: [Tool] { get }

    /// Handle a dispatched tool call for any tool whose name appears in `mcpTools`.
    func handle(toolName: String, arguments: [String: Value]?) async throws -> CallTool.Result
}
