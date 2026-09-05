# KeyValueStore Plugin -- Agent Guide

## Plugin Overview

The KeyValueStore plugin captures snapshots of key-value stores (UserDefaults, SharedPreferences, custom stores) from a connected iOS/Android device. Each snapshot contains the full state of all stores, including keys, typed values, editability, and modification history. The plugin supports bidirectional communication: agents can read current state and also observe changes over time.

## Plugin ID

- **Full ID:** `com.echo.plugin.keyvaluestore`
- **Sanitized ID / JSONL filename:** `keyvaluestore` (file: `keyvaluestore.jsonl`)

## Data Format

Each line in `keyvaluestore.jsonl` is a JSON object with this envelope:

```json
{
  "timestamp": "2026-04-03T12:00:00Z",
  "plugin_id": "keyvaluestore",
  "command": "updateSnapshot",
  "data": { ... }
}
```

The `data` field contains the raw plugin event payload. The primary event type is `updateSnapshot`, which wraps a full `EchoKeyValueStoreSnapshot`:

```json
{
  "timestamp": "2026-04-03T12:00:00Z",
  "plugin_id": "keyvaluestore",
  "data": {
    "updateSnapshot": {
      "_0": {
        "stores": [
          {
            "id": "com.example.app.defaults",
            "name": "User Defaults",
            "sfSymbol": "gearshape.fill",
            "entries": [
              {
                "key": "theme",
                "value": { "string": { "_0": "dark" } },
                "type": "string",
                "isEditable": true,
                "lastModified": 1710512000000,
                "modificationHistory": []
              },
              {
                "key": "onboarding_complete",
                "value": { "boolean": { "_0": true } },
                "type": "boolean",
                "isEditable": true,
                "modificationHistory": []
              },
              {
                "key": "launch_count",
                "value": { "integer": { "_0": 42 } },
                "type": "integer",
                "isEditable": true,
                "modificationHistory": []
              }
            ],
            "isReadOnly": false,
            "lastUpdated": 1710512000000,
            "supportedTypes": ["string", "integer", "boolean", "double", "data", "date", "array", "dictionary"]
          }
        ],
        "timestamp": 1710512000000
      }
    }
  }
}
```

### Value Encoding

Values use a tagged-union format (`EchoCodableValue`). The key is the type, and `_0` holds the value:

| Type | Example |
|------|---------|
| `string` | `{ "string": { "_0": "hello" } }` |
| `integer` | `{ "integer": { "_0": 42 } }` |
| `boolean` | `{ "boolean": { "_0": true } }` |
| `double` | `{ "double": { "_0": 3.14 } }` |
| `date` | `{ "date": { "_0": 1710512000000 } }` (ms since epoch) |
| `array` | `{ "array": { "_0": [...] } }` |
| `dictionary` | `{ "dictionary": { "_0": { ... } } }` |
| `data` | `{ "data": { "_0": "SGVsbG8=" } }` (base64) |
| `url` | `{ "url": { "_0": "https://example.com" } }` |
| `null` | `{ "null": {} }` |

### Other Event Types

Other events that may appear in the JSONL (less common):

- **`error`**: `{ "error": { "storeId": "...", "message": "..." } }` -- client-reported errors.
- **`changeConfirmation`**: `{ "changeConfirmation": { "changeId": "...", "timestamp": ..., "success": true } }` -- confirms a desktop-initiated edit.
- **`changeConflict`**: `{ "changeConflict": { "changeId": "...", "key": "...", "appValue": ..., "desktopValue": ... } }` -- a concurrent modification conflict.

## Querying Data

```bash
# Query all keyvaluestore snapshots (default limit: 50)
echoapp query keyvaluestore

# Last 5 minutes of data
echoapp query keyvaluestore --last 5m

# Limit results
echoapp query keyvaluestore --limit 10

# Compact output (one-liner summaries)
echoapp query keyvaluestore --format compact

# Query a specific session
echoapp query keyvaluestore --session <session-id>

# Tail live data as it arrives
echoapp tail keyvaluestore
```

There are no plugin-specific filters (like `--url` for networking). Use `jq` for fine-grained filtering:

```bash
# Find a specific key across all snapshots
echoapp query keyvaluestore --limit 100 | jq -r '
  .data.updateSnapshot._0.stores[].entries[]
  | select(.key == "theme")
  | "\(.key) = \(.value)"
'

# List all keys in a specific store
echoapp query keyvaluestore --limit 1 | jq -r '
  .data.updateSnapshot._0.stores[]
  | select(.id == "com.example.app.defaults")
  | .entries[].key
'

# Get all store names
echoapp query keyvaluestore --limit 1 | jq -r '
  .data.updateSnapshot._0.stores[] | "\(.id) (\(.name)) - \(.entries | length) entries"
'
```

## Common Agent Workflows

### 1. Check a feature flag or config value

```bash
echoapp query keyvaluestore --limit 1 | jq -r '
  .data.updateSnapshot._0.stores[].entries[]
  | select(.key == "feature_dark_mode_enabled")
  | .value
'
```

### 2. Verify a value changed after a user action

Query before and after snapshots to confirm a key changed:

```bash
echoapp query keyvaluestore --last 2m | jq -r '
  .data.updateSnapshot._0.stores[].entries[]
  | select(.key == "onboarding_complete")
  | "\(.value)"
'
```

### 3. List all UserDefaults stores and their sizes

```bash
echoapp query keyvaluestore --limit 1 | jq -r '
  .data.updateSnapshot._0.stores[]
  | "\(.name) [\(.id)]: \(.entries | length) entries, readOnly=\(.isReadOnly)"
'
```

### 4. Find all boolean flags

```bash
echoapp query keyvaluestore --limit 1 | jq -r '
  [.data.updateSnapshot._0.stores[].entries[] | select(.type == "boolean")]
  | .[] | "\(.key) = \(.value.boolean._0)"
'
```

### 5. Detect changes between snapshots

Compare the latest two snapshots to see what changed:

```bash
echoapp query keyvaluestore --limit 2 | jq -s '
  if length == 2 then
    (.[0].data.updateSnapshot._0.stores[].entries | map({(.key): .value}) | add) as $old |
    (.[1].data.updateSnapshot._0.stores[].entries | map({(.key): .value}) | add) as $new |
    ($new | keys[]) as $k | select($old[$k] != $new[$k]) | {key: $k, old: $old[$k], new: $new[$k]}
  else "Need at least 2 snapshots" end
'
```

### 6. Monitor for errors

```bash
echoapp query keyvaluestore --last 10m | jq 'select(.data.error) | .data.error'
```
