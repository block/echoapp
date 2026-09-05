# Accessibility Plugin

## Overview

The Accessibility plugin captures screen snapshots with accessibility element metadata from a connected iOS/Android device. It allows inspection of VoiceOver descriptions, identifiers, hints, Voice Control input labels, custom actions, and element frames. The desktop UI shows a screenshot with color-coded overlays for each element and a detail panel.

**Plugin ID:** `com.echo.plugin.accessibility`
**Sanitized ID (JSONL filename):** `accessibility`
**JSONL file:** `~/.echo/sessions/<session-id>/accessibility.jsonl`

## Data Format

Each line in `accessibility.jsonl` is a JSON object wrapping an `AccessibilityEvent`. The plugin uses bidirectional communication -- only `snapshot` events (client -> desktop) contain meaningful captured data.

### JSONL Entry Structure

```json
{
  "timestamp": "2025-04-03T10:30:00Z",
  "plugin_id": "accessibility",
  "data": {
    "snapshot": {
      "_0": {
        "imageData": "<base64-encoded PNG>",
        "elements": [
          {
            "description": "Submit Order",
            "identifier": "submit_order_button",
            "hint": "Double tap to submit your order",
            "userInputLabels": ["Submit", "Place Order"],
            "customActions": ["Increment", "Decrement"],
            "frame": { "x": 120.0, "y": 540.5, "width": 200.0, "height": 44.0 }
          },
          {
            "description": "Shopping Cart",
            "customActions": [],
            "frame": { "x": 0.0, "y": 0.0, "width": 393.0, "height": 852.0 }
          }
        ]
      }
    }
  }
}
```

### AccessibilityElement Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | VoiceOver label read when element receives focus |
| `identifier` | string | No | Accessibility identifier for UI testing (omitted when nil) |
| `hint` | string | No | Additional VoiceOver text after the description (omitted when nil) |
| `userInputLabels` | [string] | No | Voice Control input labels (omitted when nil) |
| `customActions` | [string] | Yes | Custom accessibility action names (may be empty) |
| `frame` | object | Yes | Bounding rect with `x`, `y`, `width`, `height` in screen points |

Optional fields are omitted entirely (not `null`) when the value is nil.

### Other Event Types in the JSONL

Desktop-to-client commands also appear in the file but contain no useful audit data:

```json
{"timestamp":"...","plugin_id":"accessibility","data":{"requestSnapshot":{}}}
{"timestamp":"...","plugin_id":"accessibility","data":{"sendLiveUpdates":{"_0":true}}}
```

## Querying Data

```bash
# Query all accessibility data from the current session
echoapp query accessibility

# Limit results
echoapp query accessibility --limit 10

# Show entries from the last 5 minutes
echoapp query accessibility --last 5m

# Query a specific session
echoapp query accessibility --session "2025-04-03T10-30-00_iPhone-16"

# Compact output format
echoapp query accessibility --format compact
```

There are no accessibility-specific filter flags (like `--url` for networking). Filter snapshot data by piping through `jq`:

```bash
# Get only snapshot events (skip requestSnapshot/sendLiveUpdates)
echoapp query accessibility --limit 100 | jq 'select(.data.snapshot)'

# Extract all element descriptions from snapshots
echoapp query accessibility --limit 100 | jq -r '.data.snapshot._0.elements[]?.description'

# Find elements missing an accessibility identifier
echoapp query accessibility --limit 100 | jq '.data.snapshot._0.elements[] | select(.identifier == null) | .description'

# Find elements missing a hint
echoapp query accessibility --limit 100 | jq '.data.snapshot._0.elements[] | select(.hint == null) | {description, identifier}'

# Count elements per snapshot
echoapp query accessibility --limit 100 | jq '.data.snapshot._0.elements | length'
```

## Common Agent Workflows

### Audit missing accessibility identifiers

Find elements that lack an `identifier`, which makes them hard to target in UI tests:

```bash
echoapp query accessibility --limit 50 \
  | jq -r '.data.snapshot._0.elements[] | select(.identifier == null) | "MISSING ID: \(.description) at (\(.frame.x),\(.frame.y))"'
```

### Audit missing VoiceOver hints

Find interactive elements that have no hint text:

```bash
echoapp query accessibility --limit 50 \
  | jq -r '.data.snapshot._0.elements[] | select(.hint == null and (.customActions | length > 0)) | "NO HINT: \(.description)"'
```

### Verify a specific element exists

Check that a particular accessibility identifier is present on screen:

```bash
echoapp query accessibility --last 1m \
  | jq -r '.data.snapshot._0.elements[] | select(.identifier == "submit_order_button") | {description, hint, frame}'
```

### Compare element counts across snapshots

Detect screens with few or no accessibility elements:

```bash
echoapp query accessibility --limit 20 \
  | jq '{timestamp: .timestamp, element_count: (.data.snapshot._0.elements | length // 0)}' \
  | jq 'select(.element_count != null)'
```

### Extract all unique element descriptions

Get a deduplicated list of VoiceOver labels across all captured snapshots:

```bash
echoapp query accessibility --limit 100 \
  | jq -r '.data.snapshot._0.elements[]?.description' \
  | sort -u
```

## Architecture Notes

- **Model types:** `AccessibilityEvent` (enum), `Snapshot` (imageData + elements), `AccessibilityElement`, `Rect` -- all in `Model/`
- **View model:** `AccessibilityViewModel` manages connection lifecycle, snapshot state, zoom/pan, and element selection
- **Plugin entry point:** `Plugin.swift` implements `DesktopPlugin` protocol
- **The `imageData` field** is base64-encoded PNG data. It is typically large. When processing JSONL programmatically, consider filtering it out if you only need element metadata.
