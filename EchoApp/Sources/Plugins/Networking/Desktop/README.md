# NetworkingDesktopPlugin

The NetworkingDesktopPlugin is a powerful network debugging tool that provides real-time monitoring and manipulation of network traffic in your application. It offers a comprehensive interface for inspecting HTTP requests and responses, managing fixtures, and controlling network behavior.


## Features

### 1. Network Traffic Monitoring
- **Real-time Request/Response Tracking**: Monitor all network exchanges as they happen
- **Split-View Interface**: 
  - Left pane: Filterable list of network requests
  - Right pane: Detailed request/response information
- **Search and Filter**:
  - Filter by endpoint path
  - Toggle visibility of failed/successful requests
  - Quick access to specific network calls

### 2. Request/Response Details
- **Request Information**:
  - HTTP method
  - Headers
  - Request body
  - URL and endpoint details
- **Response Analysis**:
  - Status codes with visual indicators
  - Response headers
  - Formatted response body
  - Response timing data

### 3. Advanced Features
- **JSON Highlighting**: Syntax highlighting for JSON content
- **Copy Functionality**: Quick copy options for request/response data
- **Font Size Controls**: Adjustable text size for better readability
- **Response Policy Management**:
  - Set default response policies
  - Configure per-endpoint overrides
  - Multiple response handling options

### 4. Fixture Management
- **Save Fixtures**: Capture and save response data for later use
- **Fixture Repository**: Configure and manage a local fixtures repository
- **Response Simulation**: Use fixtures to simulate network responses

### 5. Settings and Configuration
- **Visual Preferences**:
  - Toggle JSON syntax highlighting
  - Adjust display options
- **Filter Controls**:
  - Hide/show failed requests
  - Hide/show successful requests
- **Response Policies**:
  - Configure default behaviors
  - Set up endpoint-specific rules
  - Manage response overrides

## Usage

1. **Monitor Network Traffic**:
   - Watch real-time network requests in the left pane
   - Click on any request to view details
   - Use the search field to filter requests by endpoint

2. **Inspect Request/Response Details**:
   - View complete request information in the right pane
   - Examine response data, including status codes and bodies
   - Use the font size controls to adjust text visibility

3. **Manage Response Behaviors**:
   - Configure default response policies
   - Set up endpoint-specific overrides
   - Save and manage fixtures for testing

4. **Configure Settings**:
   - Set up the fixtures repository path
   - Configure display preferences
   - Manage response policies and overrides

## Integration with Development Workflow

The NetworkingDesktopPlugin integrates seamlessly with your development workflow:
- Debug network issues in real-time
- Save and reuse network responses for testing
- Configure consistent response behaviors across your application
- Export network data for documentation or troubleshooting

## MCP (Model Context Protocol) Server

Echo exposes a built-in MCP server on port `34001`, allowing AI agents (Claude Desktop, Goose, etc.) to inspect live network traffic directly from a conversation.

### Prerequisites

- [`uv`](https://docs.astral.sh/uv/) is installed (`brew install uv`) — used to run `mcp-proxy`

### Setup

Add the following to your MCP client config, pointing at the `echo-mcp` binary bundled inside EchoApp.app:

**Claude Code** (run once in terminal):
```bash
claude mcp add --scope user echo -- ~/.config/echo/echo-mcp
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "echo": {
      "command": "/Users/<you>/.config/echo/echo-mcp"
    }
  }
}
```

Restart your MCP client after saving. When Echo launches it writes `~/.config/echo/mcp.json` (port/URL) and copies the `echo-mcp` wrapper to `~/.config/echo/echo-mcp` — no reconfiguration needed if the app moves or the port changes.

### Available Tools

| Tool | Description |
|------|-------------|
| `list_devices` | Lists devices. Connected device has `status: connected`; devices discovered via Bonjour or ADB have `status: available` and `type: ios` or `type: android`. Works even before a device is connected. |
| `connect_device` | Connects to an available device by `id` (from `list_devices`). Same as tapping the device in Echo UI. |
| `disconnect_device` | Clears the currently connected device from the MCP session. |
| `list_exchanges` | Lists captured network packets with optional filters: `url`, `method`, `status_code`, `last_seconds`, `since`, `limit`, `offset`, `device_id` |
| `get_exchange` | Returns full details of one packet: request headers, request body, response headers, response body, status code |
| `search_exchanges` | Searches captured packets by URL substring |
| `clear_exchanges` | Clears all captured network packets |

### Example Usage

Ask your AI agent:
- *"What devices are available?"*
- *"Connect to my iPhone"*
- *"Show me all failed API calls from the last 30 seconds"*
- *"What were the request and response bodies for the /orders/sync call?"*
- *"Search for any calls to the catalog endpoint"*
- *"Clear all captured network traffic"*

### How It Works

```
AI Agent (Claude Desktop / Goose)
    ↕ stdio
echo-mcp  →  reads ~/.config/echo/mcp.json
    ↕ HTTP (mcp-proxy)
EchoApp.app MCP server on port 34001
    ↕
Live network exchanges
```