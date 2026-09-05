# Logging Plugin

## Overview

The Logging plugin captures real-time application logs from a connected iOS/Android device and displays them in a structured, filterable table. Logs flow unidirectionally from the client app to the Echo desktop app. Each log entry contains a timestamp, log level, priority, and message.

## Plugin ID

- **Full ID**: `com.echo.plugin.logging`
- **Sanitized ID**: `logging` (used for JSONL filenames and `echoapp` queries)
- **JSONL file**: `logging.jsonl` in the session directory

## Data Format

Each line in `logging.jsonl` is a JSON object with this structure:

```json
{
  "timestamp": "2024-03-15T14:32:01Z",
  "plugin_id": "logging",
  "data": {
    "id": "c3d4e5f6-a1b2-7890-abcd-1234567890ab",
    "columnItems": {
      "Time": "2024-03-15 14:32:01.234",
      "Level": "error",
      "Priority": "high",
      "Message": "Failed to fetch user profile: HTTP 503 Service Unavailable"
    }
  }
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string (ISO 8601) | When Echo captured this entry. Used by `--last` filter. |
| `plugin_id` | string | Always `"logging"`. |
| `data.id` | string | Unique row identifier (typically a UUID). |
| `data.columnItems.Time` | string | Timestamp from the client app (format varies by app). |
| `data.columnItems.Level` | string | Log level: `"debug"`, `"info"`, `"warning"`, `"error"`, etc. |
| `data.columnItems.Priority` | string | Log priority: `"low"`, `"medium"`, `"high"`, etc. |
| `data.columnItems.Message` | string | The log message content. |

Additional keys beyond `Time`, `Level`, `Priority`, and `Message` may appear in `columnItems` depending on the client app.

## Querying Data

Use `echoapp query logging` to search captured logs. The `--level` filter matches against top-level `data.level` or `data.log_level` fields (case-insensitive). **Note**: Logging rows store the level inside `data.columnItems.Level`, which `--level` does not check. If `--level` returns no results, use `grep` to filter by level instead:

```bash
echoapp query logging --last 5m | grep -i '"Level":"error"'
```

```bash
# Get the last 50 log entries (default)
echoapp query logging

# Filter by log level
echoapp query logging --level error
echoapp query logging --level debug

# Filter by time window
echoapp query logging --last 5m
echoapp query logging --last 1h

# Combine filters
echoapp query logging --level error --last 10m --limit 20

# Compact output (one-line summaries)
echoapp query logging --format compact

# Increase result limit
echoapp query logging --level warning --limit 200
```

### Filter Reference

| Flag | Description |
|------|-------------|
| `--level <level>` | Filter by log level (e.g., `error`, `debug`, `info`). Case-insensitive. |
| `--last <duration>` | Only entries within this time window. Supports `s`, `m`, `h`, `d` (e.g., `5m`, `1h`, `2d`). |
| `--limit <n>` | Max results to return (default: 50). |
| `--format <fmt>` | Output format: `json` (default) or `compact`. |
| `--session <id>` | Query a specific session instead of the current one. |

## Common Agent Workflows

### Diagnosing a crash or error

```bash
# 1. Check for recent errors
echoapp query logging --level error --last 5m

# 2. Get broader context around the error timeframe
echoapp query logging --last 5m --limit 200
```

### Monitoring logs during a user action

```bash
# 1. Tail all logs while reproducing an issue
echoapp query logging --last 30s

# 2. Filter to errors and warnings only
echoapp query logging --level error --last 1m
echoapp query logging --level warning --last 1m
```

### Searching for specific log messages

Log message content is inside `data.columnItems.Message`. Since `echoapp query` does not have a `--message` text filter, pipe through `jq` or `grep`:

```bash
# Find logs mentioning a specific keyword
echoapp query logging --limit 200 | grep -i "timeout"

# Extract just timestamps and messages with jq
echoapp query logging --level error | jq -r '[.data.columnItems.Time, .data.columnItems.Message] | join(" | ")'
```

### Correlating logs with network requests

```bash
# 1. Find failing network requests
echoapp query network --status 500 --last 5m

# 2. Check app logs around the same time for context
echoapp query logging --level error --last 5m
```

### Deep linking into the UI

Open a filtered log view in the Echo desktop app:

```
echo://plugin/com.echo.plugin.logging/search?query=your_search_term
```
