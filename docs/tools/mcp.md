---
title: MCP server
description: Let an MCP-compatible coding agent query live EchoApp network and analytics data.
section: Tools
permalink: /tools/mcp/
---

# MCP server

EchoApp includes a local Model Context Protocol server. An MCP-compatible coding assistant can list
devices and inspect live network and analytics data while the desktop app is running.

## How it works

EchoApp starts a local HTTP MCP server and writes its current address to
`~/.config/echo/mcp.json`. It also installs a small stdio bridge at `~/.config/echo/echo-mcp` so MCP
clients can launch one stable command even when EchoApp's local port changes.

The bridge uses `uvx mcp-proxy`; install [uv](https://docs.astral.sh/uv/) before registering it.

## Register the bridge

For Claude Code:

```sh
claude mcp add --scope user echo -- "$HOME/.config/echo/echo-mcp"
```

For an MCP client that uses JSON configuration:

```json
{
  "mcpServers": {
    "echo": {
      "command": "/Users/you/.config/echo/echo-mcp"
    }
  }
}
```

Use an absolute path in JSON because clients do not consistently expand `$HOME`. Launch EchoApp at
least once before registering the bridge.

## Available tools

| Tool | Purpose |
|---|---|
| `list_devices` | Discover Bonjour and ADB clients. |
| `connect_device` | Connect EchoApp to a discovered client. |
| `disconnect_device` | Clear the current MCP device session. |
| `list_exchanges` | List captured network exchanges with optional filters. |
| `get_exchange` | Read the full request and response for one exchange. |
| `search_exchanges` | Search exchanges by URL substring. |
| `clear_exchanges` | Clear the in-memory network capture. |
| `list_analytics_events` | List captured analytics events with optional filters. |
| `get_analytics_events` | Read full analytics event details. |

Plugin-provided tools are discovered from the plugins loaded into EchoApp, so the exact list can
grow without changing the MCP host.

## Verify the setup

Open EchoApp, then ask the MCP client to call `list_devices`. An empty result means the bridge and
server are working but no clients are discoverable. A launch or connection error usually means
EchoApp is closed, the bridge has not been installed yet, or `uvx` is not on the MCP client's PATH.

## Privacy

MCP output can include request bodies, headers, analytics properties, identifiers, and other
sensitive debug data. Review tool results before they enter a chat transcript, redact secrets, and
do not give a remote model access to data you are not authorized to share.

For broader capture support or scripting, use the [command-line interface](../cli/).
