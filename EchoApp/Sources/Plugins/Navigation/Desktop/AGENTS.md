# Navigation Plugin - Agent Guide

## Overview

The Navigation plugin visualizes the navigation stack of a connected mobile app in real-time. It displays the current screen, the backstack (screens the user can navigate back to), and metadata about each navigation event. This is a **read-only** plugin -- it receives snapshots from the mobile app but does not send commands back.

## Plugin ID

- **Bundle ID**: `com.echo.plugin.navigation`
- **Sanitized ID**: `navigation` (used for JSONL filenames and CLI queries)
- **JSONL filename**: `navigation.jsonl`

## Data Format

Each line in `navigation.jsonl` is a JSON object with the following wrapper structure:

```json
{
  "timestamp": "2025-04-03T14:30:00Z",
  "plugin_id": "navigation",
  "data": {
    "currentScreen": {
      "id": "screen-uuid",
      "title": "Home",
      "route": "/home",
      "className": "HomeViewController",
      "parameters": {
        "userId": "123",
        "tab": "feed"
      },
      "timestamp": 1707736200000
    },
    "backstack": [
      {
        "id": "screen-uuid-2",
        "title": "Login",
        "route": "/login",
        "className": "LoginViewController",
        "parameters": null,
        "timestamp": 1707736100000
      }
    ],
    "navigationType": "push",
    "timestamp": 1707736200000
  }
}
```

### Key fields

| Field | Type | Description |
|---|---|---|
| `data.currentScreen` | `NavigationScreen` | The active screen the user is viewing |
| `data.backstack` | `[NavigationScreen]` | Screens the user can navigate back to (most recent first) |
| `data.navigationType` | `String?` | Navigation action type: `"push"`, `"back"`, `"finish"`, `"modal"`, etc. |
| `data.timestamp` | `Number` | Epoch milliseconds when the snapshot was taken |

### NavigationScreen fields

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique identifier for this screen instance |
| `title` | `String` | Human-readable screen title |
| `route` | `String` | Route path (e.g., `/home`, `/settings/profile`) |
| `className` | `String?` | View controller or fragment class name |
| `parameters` | `{String: String}?` | Key-value parameters passed to the screen |
| `timestamp` | `Number?` | Epoch milliseconds when the screen was entered |

## Querying Data

The Navigation plugin does not have dedicated CLI filter flags (unlike networking's `--url` or analytics' `--event`). Use the generic query options:

```bash
# Get the latest navigation snapshots (default limit: 50)
echoapp query navigation

# Get the last 10 snapshots
echoapp query navigation --limit 10

# Get snapshots from the last 5 minutes
echoapp query navigation --last 5m

# Compact output (one-line summaries)
echoapp query navigation --format compact

# Query a specific session
echoapp query navigation --session "2025-04-03T14-30-00_iPhone-16"
```

For fine-grained filtering (e.g., by route or screen title), pipe the JSON output through `jq`:

```bash
# Find all snapshots where the current screen route contains "/settings"
echoapp query navigation --format json | jq 'select(.data.currentScreen.route | test("/settings"))'

# Get just the current screen titles
echoapp query navigation --format json | jq -r '.data.currentScreen.title'

# Find navigation events of type "back"
echoapp query navigation --format json | jq 'select(.data.navigationType == "back")'

# Count how many screens are in the backstack for each snapshot
echoapp query navigation --format json | jq '{timestamp: .timestamp, backstack_depth: (.data.backstack | length), current: .data.currentScreen.title}'
```

## Common Agent Workflows

### Verify a deep link lands on the correct screen

```bash
# After triggering a deep link, check the current screen
echoapp query navigation --last 10s --limit 1 --format json | \
  jq '.data.currentScreen | {route, title, parameters}'
```

### Trace a user journey through screens

```bash
# Get the full navigation history and extract the screen sequence
echoapp query navigation --last 5m --format json | \
  jq -r '[.timestamp, .data.navigationType // "initial", .data.currentScreen.route] | @tsv'
```

### Check for unexpected backstack growth

```bash
# Monitor backstack depth over time
echoapp query navigation --last 10m --format json | \
  jq '{time: .timestamp, depth: (.data.backstack | length), screen: .data.currentScreen.title}'
```

### Validate navigation parameters

```bash
# Check what parameters were passed to a specific screen
echoapp query navigation --format json | \
  jq 'select(.data.currentScreen.route == "/profile") | .data.currentScreen.parameters'
```

### Detect navigation loops

```bash
# Find repeated routes in sequence (potential loops)
echoapp query navigation --last 10m --format json | \
  jq -r '.data.currentScreen.route' | uniq -d
```

## Architecture Notes

- The plugin only has a `Desktop/` directory (no `API/` directory).
- The desktop plugin class is `NavigationDesktopPlugin` in `Plugin.swift`.
- `NavigationViewModel` holds a single `@Published` property `currentSnapshot: NavigationSnapshot?` -- it always reflects the latest snapshot received, not a history.
- The mobile app sends a new `NavigationSnapshot` via `PluginConnection` on every navigation event. History is only available through the JSONL file, not the live plugin state.
