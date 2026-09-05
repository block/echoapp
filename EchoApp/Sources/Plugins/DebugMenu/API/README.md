# Debug Menu Plugin API

Provides a bidirectional interface for viewing and controlling the connected app's debug menu. The desktop displays debug menu sections and items (toggles, pickers, actions, text inputs) and can send commands to change their state.

## Communication Pattern

**Direction:** Bidirectional

- **Client -> Desktop:** `EchoDebugMenuClientEvent` — sends snapshots of the full debug menu, item update confirmations, action completion results, and error reports.
- **Desktop -> Client:** `EchoDebugMenuDesktopEvent` — requests snapshots and sends commands to modify individual items (set toggles, select options, execute actions, set text values).

All messages are JSON-encoded instances of the respective event enum, transported as the `data` field within an Echo `PluginPayload`.

## Message Types

### EchoDebugMenuClientEvent

**Direction:** Client -> Desktop

A tagged union whose JSON is a single-key object.

---

#### Variant: `updateSnapshot`

Sends a full snapshot of the debug menu.

```json
{
  "updateSnapshot": {
    "_0": <EchoDebugMenuSnapshot>
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | EchoDebugMenuSnapshot | Yes | Complete snapshot of all debug menu sections and items. |

---

#### Variant: `itemUpdated`

Confirms that a specific item's state was changed on the client.

```json
{
  "itemUpdated": {
    "itemId": "env-selector",
    "newType": { "picker": { "options": ["Production", "Staging", "Dev"], "selectedIndex": 1 } }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the updated item. |
| `newType` | EchoDebugMenuItemType | Yes | The item's new type/value state. |

---

#### Variant: `actionCompleted`

Reports the result of a triggered action.

```json
{
  "actionCompleted": {
    "itemId": "clear-cache",
    "success": true,
    "message": "Cache cleared (42 MB freed)"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the action that was executed. |
| `success` | boolean | Yes | Whether the action completed successfully. |
| `message` | string | No | Human-readable result or error message. |

---

#### Variant: `error`

Reports a general error.

```json
{
  "error": {
    "message": "Debug menu not available in release builds"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | Yes | Human-readable error description. |

---

### EchoDebugMenuDesktopEvent

**Direction:** Desktop -> Client

---

#### Variant: `requestSnapshot`

Asks the client to send the current debug menu state.

```json
{
  "requestSnapshot": {}
}
```

No fields.

---

#### Variant: `setToggle`

Requests the client to change a toggle value.

```json
{
  "setToggle": {
    "itemId": "show-debug-overlay",
    "isOn": true
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the toggle item. |
| `isOn` | boolean | Yes | The desired toggle state. |

---

#### Variant: `selectOption`

Requests the client to change a picker's selected option.

```json
{
  "selectOption": {
    "itemId": "env-selector",
    "selectedIndex": 2
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the picker item. |
| `selectedIndex` | integer | Yes | Zero-based index of the option to select. |

---

#### Variant: `executeAction`

Requests the client to execute a one-shot action.

```json
{
  "executeAction": {
    "itemId": "clear-cache"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the action item. |

---

#### Variant: `setTextValue`

Requests the client to update a text input value.

```json
{
  "setTextValue": {
    "itemId": "custom-api-url",
    "value": "https://staging.example.com/api"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | string | Yes | The ID of the text input item. |
| `value` | string | Yes | The text value to set. |

---

## Data Models

### EchoDebugMenuSnapshot

```json
{
  "sections": [<EchoDebugMenuSection>],
  "timestamp": 1710512000000
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sections` | array of EchoDebugMenuSection | Yes | All debug menu sections. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch. |

---

### EchoDebugMenuSection

```json
{
  "id": "feature-flags",
  "title": "Feature Flags",
  "icon": "flag",
  "items": [<EchoDebugMenuItem>]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier for this section. |
| `title` | string | Yes | Display name. |
| `icon` | string | No | SF Symbol name for the section icon. |
| `items` | array of EchoDebugMenuItem | Yes | Items in this section. |

---

### EchoDebugMenuItem

```json
{
  "id": "show-debug-overlay",
  "title": "Show Debug Overlay",
  "subtitle": "Displays FPS counter and memory usage",
  "type": { "toggle": { "isOn": false } },
  "tags": ["ui", "performance"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier. |
| `title` | string | Yes | Display name. |
| `subtitle` | string | No | Description or help text. |
| `type` | EchoDebugMenuItemType | Yes | The item type and its current value. |
| `tags` | array of string | No | Searchable tags for categorization. |

---

### EchoDebugMenuItemType

A tagged union. Each variant includes its current state:

| Variant | JSON | Description |
|---------|------|-------------|
| `toggle` | `{ "toggle": { "isOn": true } }` | Boolean on/off switch. |
| `picker` | `{ "picker": { "options": ["A", "B"], "selectedIndex": 0 } }` | Single-select from a list of options. |
| `action` | `{ "action": {} }` | One-shot trigger button. |
| `textInput` | `{ "textInput": { "value": "https://...", "placeholder": "Enter URL" } }` | Freeform text field. |

## Encoding Notes

1. **Tagged union format:** Both event enums and `EchoDebugMenuItemType` use Swift's compiler-synthesized `Codable`. Each case is a JSON object with a single key (the case name) containing an object with the associated values.

2. **Date encoding:** All `Date` values are encoded as **integers representing milliseconds since Unix epoch**. The `PluginConnection` uses a custom encoder for this.

3. **Optional fields are absent, not null:** When an optional field is nil, the key is omitted entirely.

## Examples

### Client sends a debug menu snapshot

```json
{
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
            },
            {
              "id": "show-debug-overlay",
              "title": "Debug Overlay",
              "subtitle": "FPS counter and memory usage",
              "type": { "toggle": { "isOn": true } },
              "tags": ["ui", "performance"]
            }
          ]
        },
        {
          "id": "environment",
          "title": "Environment",
          "icon": "server.rack",
          "items": [
            {
              "id": "api-env",
              "title": "API Environment",
              "type": { "picker": { "options": ["Production", "Staging", "Dev"], "selectedIndex": 0 } }
            },
            {
              "id": "custom-api-url",
              "title": "Custom API URL",
              "subtitle": "Overrides the selected environment",
              "type": { "textInput": { "value": "", "placeholder": "https://custom.api.example.com" } }
            }
          ]
        },
        {
          "id": "actions",
          "title": "Actions",
          "icon": "bolt",
          "items": [
            {
              "id": "clear-cache",
              "title": "Clear Cache",
              "subtitle": "Removes all cached data",
              "type": { "action": {} }
            },
            {
              "id": "force-sync",
              "title": "Force Sync",
              "type": { "action": {} }
            }
          ]
        }
      ],
      "timestamp": 1710512000000
    }
  }
}
```

### Desktop sets a toggle

```json
{
  "setToggle": {
    "itemId": "enable-new-checkout",
    "isOn": true
  }
}
```

### Desktop selects a picker option

```json
{
  "selectOption": {
    "itemId": "api-env",
    "selectedIndex": 1
  }
}
```

### Desktop executes an action

```json
{
  "executeAction": {
    "itemId": "clear-cache"
  }
}
```

### Client confirms action completion

```json
{
  "actionCompleted": {
    "itemId": "clear-cache",
    "success": true,
    "message": "Cache cleared (42 MB freed)"
  }
}
```

### Desktop sets a text value

```json
{
  "setTextValue": {
    "itemId": "custom-api-url",
    "value": "https://staging.example.com/api/v2"
  }
}
```
