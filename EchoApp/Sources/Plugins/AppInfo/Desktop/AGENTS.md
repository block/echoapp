# AppInfo Plugin - Agent Guide

## Plugin Overview

The AppInfo plugin displays key-value application information from a connected device, organized by scope. Data flows **unidirectionally** from the client to the desktop -- the plugin receives a full snapshot of entries each time the client sends data (replacing all previous entries). Typical data includes tokens, environment info, app version, build numbers, and configuration values.

## Plugin ID

- **Full ID**: `com.echo.plugin.appinfo`
- **Sanitized ID**: `appinfo` (used for JSONL filenames and `echoapp` queries)
- **JSONL filename**: `appinfo.jsonl`

## Data Format

Each line in `appinfo.jsonl` is a JSON object with this structure:

```json
{
  "timestamp": "2025-04-03T10:30:00Z",
  "plugin_id": "appinfo",
  "data": [
    {
      "scope": "1 - Tokens",
      "key": "Customer Token",
      "value": "CUST_ABC123"
    },
    {
      "scope": "1 - Tokens",
      "key": "Device Token",
      "value": "DEV_XYZ789"
    },
    {
      "scope": "2 - Environment",
      "key": "Environment",
      "value": "Production"
    },
    {
      "scope": "2 - Environment",
      "key": "API Base URL",
      "value": "https://api.example.com"
    },
    {
      "scope": "3 - App",
      "key": "App Version",
      "value": "6.42.1"
    },
    {
      "scope": "3 - App",
      "key": "Build Number",
      "value": "20240301.1"
    }
  ]
}
```

### Key details

- The `data` field is a **JSON array** of entry objects (not a single object).
- Each entry has exactly three required string fields: `scope`, `key`, `value`.
- Each JSONL line represents a **complete snapshot** -- it replaces the previous state entirely.
- The most recent line is the current state of the app's info.
- Scopes are conventionally prefixed with numbers for ordering (e.g., `"1 - Tokens"`, `"2 - Environment"`).

## Querying Data

**Important**: `echoapp query` reads JSONL from the top and stops at `--limit`, so `--limit 1` returns the **oldest** entry, not the newest. Use `tail -l 1` on the JSONL file or pipe through `tail` to get the latest snapshot.

```bash
# Get all appinfo snapshots from the current session
echoapp query appinfo

# Get the latest snapshot (newest entry is at the end of the file)
echoapp tail appinfo -l 1

# Get snapshots from the last 10 minutes
echoapp query appinfo --last 10m

# Query a specific session
echoapp query appinfo --session <session-id>
```

**Note**: The `--url`, `--method`, `--status`, `--event`, and `--level` filters are not applicable to the appinfo plugin. Use `jq` for field-level filtering:

```bash
# Extract a specific key (e.g., App Version) from the latest snapshot
echoapp tail appinfo -l 1 | jq '.data[] | select(.key == "App Version") | .value'

# List all scopes in the latest snapshot
echoapp tail appinfo -l 1 | jq '[.data[].scope] | unique'

# Get all entries in a specific scope
echoapp tail appinfo -l 1 | jq '.data[] | select(.scope == "2 - Environment")'

# Get the customer token
echoapp tail appinfo -l 1 | jq -r '.data[] | select(.key == "Customer Token") | .value'
```

## Common Agent Workflows

### 1. Verify app environment before testing

```bash
# Confirm the app is connected to the expected environment
echoapp tail appinfo -l 1 | jq -r '.data[] | select(.key == "Environment") | .value'
# Expected: "Production" or "Staging"
```

### 2. Get app version and build number

```bash
echoapp tail appinfo -l 1 | jq -r '.data[] | select(.scope | startswith("3")) | "\(.key): \(.value)"'
```

### 3. Extract customer token for cross-referencing

```bash
CUSTOMER_TOKEN=$(echoapp tail appinfo -l 1 | jq -r '.data[] | select(.key == "Customer Token") | .value')
echo "Customer: $CUSTOMER_TOKEN"
# Use the token with other tools (e.g., customer lookups)
```

### 4. Dump full app info as a readable summary

```bash
echoapp tail appinfo -l 1 | jq -r '.data | group_by(.scope)[] | "\(.[0].scope)\n" + (map("  \(.key): \(.value)") | join("\n")) + "\n"'
```

### 5. Detect environment or config changes over time

```bash
# Compare the earliest and latest snapshots to see what changed
echoapp query appinfo | jq -s '[.[0].data, .[-1].data] | [.[0][] as $a | .[1][] | select(.key == $a.key and .value != $a.value) | {key, old: $a.value, new: .value}] | .[]'
```
