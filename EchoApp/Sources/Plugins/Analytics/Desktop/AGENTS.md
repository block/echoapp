# Analytics Desktop Plugin

## Overview

The Analytics plugin captures and displays real-time analytics events from connected iOS/Android apps. Events flow **unidirectionally** from client to desktop as `EchoTableRow` objects. The desktop plugin buffers up to 2,000 events in chronological order and provides filtering, search, and deep linking.

- **Plugin ID:** `com.echo.plugin.analytics`
- **Sanitized ID (JSONL filename):** `analytics` (file: `analytics.jsonl`)
- **Display name:** Analytics
- **Direction:** Client -> Desktop (unidirectional, no messages sent back)

## Data Format

### JSONL Structure (on disk)

Each line in `analytics.jsonl` is a standalone JSON object:

```json
{"timestamp":"2026-04-03T14:32:01Z","plugin_id":"analytics","data":{"id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","columnItems":{"Time":"2026-04-03 14:32:01","Source":"Analytics","Event":"AppNavigate","Raw Message":"{\"screen\":\"home\",\"source\":\"tab_bar\"}","Properties":"screen=home, source=tab_bar"}}}
```

Fields:
- `timestamp` -- ISO8601 timestamp when the event was captured
- `plugin_id` -- always `"analytics"`
- `data` -- the `EchoTableRow` payload containing:
  - `id` -- unique row identifier (UUID)
  - `columnItems` -- key-value pairs with these expected columns:

| Column Key     | Description                        | Visible by default |
|----------------|------------------------------------|--------------------|
| `Time`         | Timestamp of the analytics event   | Yes (100pt)        |
| `Source`       | Origin of the event (e.g., the app's analytics SDK) | Yes (80pt, filterable) |
| `Event`        | Name of the analytics event        | Yes (300pt, filterable) |
| `Raw Message`  | Raw JSON payload                   | No (detail view)   |
| `Properties`   | Event properties/metadata          | No (detail view)   |

### Example JSONL entries

```jsonl
{"timestamp":"2026-04-03T14:32:01Z","plugin_id":"analytics","data":{"id":"550e8400-e29b-41d4-a716-446655440000","columnItems":{"Time":"2026-04-03 14:32:01","Source":"Analytics","Event":"AppNavigate","Raw Message":"{\"screen\":\"home\",\"source\":\"tab_bar\"}","Properties":"screen=home, source=tab_bar"}}}
{"timestamp":"2026-04-03T14:32:05Z","plugin_id":"analytics","data":{"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","columnItems":{"Time":"2026-04-03 14:32:05","Event":"ButtonTapped","Properties":"button_id=send_money"}}}
{"timestamp":"2026-04-03T14:32:09Z","plugin_id":"analytics","data":{"id":"d290f1ee-6c54-4b01-90e6-d701748f0851","columnItems":{"Time":"2026-04-03 14:32:09","Source":"Internal","Event":"ScreenView","Raw Message":"{\"screen\":\"transfer\",\"flow\":\"p2p\"}","Properties":"screen=transfer, flow=p2p"}}}
```

## Querying Data with echoapp

### Query analytics events

```bash
# All analytics events (default limit 50)
echoapp query analytics

# Filter by exact event name (case-insensitive match)
echoapp query analytics --event AppNavigate

# Filter by time window (last 5 minutes)
echoapp query analytics --last 5m

# Combine filters with a higher limit
echoapp query analytics --event ScreenView --last 1h --limit 200

# Compact output (one-line summaries)
echoapp query analytics --event ButtonTapped --format compact

# Query a specific session
echoapp query analytics --session 2026-04-03T14-32-01_iPhone-17-Pro
```

### Tail live analytics events

```bash
# Tail last 10 events and follow for new ones
echoapp tail analytics -f

# Show last 20 events without following
echoapp tail analytics --lines 20
```

### Event name matching

The `--event` filter checks the `data` object for:
1. `data.event` or `data.event_name` flat fields (case-insensitive exact match)
2. `data.columnItems` as an array of `{"key":..., "value":...}` objects, matching against the `value` field

**Note**: The JSONL `columnItems` field may be serialized as either a flat dict (`{"Event": "AppNavigate"}`) or an array of key-value objects (`[{"key": "Event", "value": "AppNavigate"}]`). The `--event` array matching only works with the array-of-objects format. If `--event` returns no matches for events you can see in the raw data, use `grep` instead:

```bash
echoapp query analytics | grep -i "AppNavigate"
```

## Common Agent Workflows

### 1. Verify an analytics event fires after an action

```bash
SESS="/tmp/echo-data/current"
SCRIPTS="<echoapp-skill-dir>/scripts"

# Record baseline
"$SCRIPTS/echo-diff.sh" baseline "$SESS"

# Trigger the action (e.g., navigate to a screen)
xcrun simctl openurl booted "myapp://example.com/launch/transfer"

# Wait for events
sleep 5

# Show only new events
"$SCRIPTS/echo-diff.sh" diff "$SESS"
```

### 2. Check if a specific event exists in the session

```bash
echoapp query analytics --event "ScreenView" --limit 5
# If output says "No matching entries found." the event was not captured.
```

### 3. Inspect event properties

```bash
# Get full detail (includes Raw Message and Properties columns)
echoapp query analytics --event "AppNavigate" --limit 1
```

Then parse the `data.columnItems.Properties` or `data.columnItems.Raw Message` field from the JSON output.

### 4. Count events of a specific type

```bash
echoapp query analytics --event "ButtonTapped" --limit 10000 | wc -l
```

### 5. Use MCP tools (when EchoApp.app is running with MCP enabled)

The plugin exposes two MCP tools:

- **`list_analytics_events`** -- returns `Time`, `Source`, and `Event` name. Supports `event_name`, `last_seconds`, `since`, `limit`, and `offset` parameters.
- **`get_analytics_events`** -- returns full detail including `Raw Message` and `Properties`. Same filter parameters.

### 6. Deep link to filter in EchoApp.app UI

```
echo://plugin/com.echo.plugin.analytics/search?query=AppNavigate
```

## Code Structure

- `Plugin.swift` -- `AnalyticsDesktopPlugin` implementing `DesktopPlugin` and `DeepLinkHandler`
- `MCPToolProvider.swift` -- `AnalyticsMCPToolProvider` exposing `list_analytics_events` and `get_analytics_events` MCP tools
- `PluginInfo.plist` -- plugin metadata (ID, version, display name)
