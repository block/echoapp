# Debug Menu Plugin - Agent Guide

## Overview

The Debug Menu plugin exposes the connected mobile app's debug menu as both a desktop UI and CLI commands. Agents can list all debug settings, toggle feature flags, switch API environments, execute debug actions, and set text values — all without navigating the app's UI.

## Plugin ID

- **Bundle ID**: `com.echo.plugin.debugmenu`
- **Sanitized ID**: `debugmenu` (used for JSONL filenames and CLI queries)
- **JSONL filename**: `debugmenu.jsonl`

## CLI Commands

All mutation commands require a live `echoapp connect` session.

### List debug menu items

```bash
# List everything
echoapp debugmenu list

# Filter by section title (case-insensitive)
echoapp debugmenu list --section "Feature Flags"

# Search by title, subtitle, or tags
echoapp debugmenu list --search "checkout"

# Filter by type: toggle, picker, action, textInput
echoapp debugmenu list --type toggle

# JSON output for programmatic use
echoapp debugmenu list --format json
```

### Set a toggle

```bash
echoapp debugmenu set-toggle <item-id> --on
echoapp debugmenu set-toggle <item-id> --off
```

### Select a picker option

```bash
# Zero-based index
echoapp debugmenu select <item-id> <index>
echoapp debugmenu select api-env 1  # e.g., Staging
```

### Execute an action

```bash
echoapp debugmenu execute <item-id>
echoapp debugmenu execute clear-cache
```

### Set a text value

```bash
echoapp debugmenu set-text <item-id> "<value>"
echoapp debugmenu set-text custom-api-url "https://staging.example.com"
```

## Data Format

Each line in `debugmenu.jsonl` is a JSON object with this structure:

```json
{
  "timestamp": "2025-04-03T14:30:00Z",
  "plugin_id": "debugmenu",
  "data": {
    "updateSnapshot": {
      "_0": {
        "sections": [
          {
            "id": "feature-flags",
            "title": "Feature Flags",
            "icon": "flag",
            "items": [
              {
                "id": "enable-new-checkout",
                "title": "New Checkout Flow",
                "subtitle": "Uses the redesigned checkout experience",
                "type": { "toggle": { "isOn": false } },
                "tags": ["checkout", "experiment"]
              }
            ]
          }
        ],
        "timestamp": 1710512000000
      }
    }
  }
}
```

### EchoDebugMenuItemType variants

| Type | JSON | Description |
|------|------|-------------|
| toggle | `{ "toggle": { "isOn": true } }` | Boolean switch |
| picker | `{ "picker": { "options": ["A", "B"], "selectedIndex": 0 } }` | Single-select from options |
| action | `{ "action": {} }` | One-shot trigger |
| textInput | `{ "textInput": { "value": "...", "placeholder": "..." } }` | Freeform text field |

## Common Agent Workflows

### Enable a feature flag

```bash
# 1. Find the toggle
echoapp debugmenu list --type toggle --search "checkout"
# 2. Set it
echoapp debugmenu set-toggle enable-new-checkout --on
```

### Switch API environment

```bash
# 1. Find the environment picker
echoapp debugmenu list --section "environment"
# 2. See available options (output includes options with indices)
# 3. Select the desired environment
echoapp debugmenu select api-env 1  # e.g., Staging
```

### Clear cache and force sync

```bash
echoapp debugmenu execute clear-cache
echoapp debugmenu execute force-sync
```

### Set a custom API URL

```bash
echoapp debugmenu set-text custom-api-url "https://staging.example.com/api/v2"
```

### Get all debug state as JSON (for programmatic parsing)

```bash
echoapp debugmenu list --format json
```

## Architecture Notes

- The plugin has both `API/` and `Desktop/` directories.
- Desktop plugin class: `DebugMenuDesktopPlugin` in `Plugin.swift`.
- `DebugMenuViewModel` holds `@Published` sections as `[EchoDebugMenuSection]`.
- Communication is bidirectional: desktop/CLI sends commands (`setToggle`, `selectOption`, `executeAction`, `setTextValue`), client responds with snapshots and confirmations.
- CLI mutation commands send events via HTTP to the running `echoapp connect` server's `/api/send` endpoint, which forwards them to the device over WebSocket.
- Local optimistic updates: toggle/picker/text changes are applied locally immediately in the desktop UI, then confirmed by the client via `itemUpdated` events.
