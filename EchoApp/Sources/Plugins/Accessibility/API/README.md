# Accessibility Plugin API

The Accessibility plugin captures screen snapshots along with accessibility element metadata from a connected client app, allowing developers to visually inspect and verify accessibility implementations. The desktop displays a screenshot with color-coded overlays for each accessibility element and a detail panel showing element properties.

## Communication Pattern

**Direction:** Bidirectional

Both the desktop and the client send and receive `AccessibilityEvent` messages over the plugin connection. All messages are JSON-encoded instances of the `AccessibilityEvent` enum, transported as the `data` field within an Echo `PluginPayload`.

- **Desktop -> Client:** `requestSnapshot` (asks the client to capture a snapshot) and `sendLiveUpdates` (tells the client whether to continuously send snapshots).
- **Client -> Desktop:** `snapshot` (delivers a captured screen image and its accessibility elements).

Encoding uses the `PluginConnection` encoder/decoder, which has a custom date strategy (milliseconds since Unix epoch). Since this plugin has no `Date` fields, the observable encoding is identical to a default `JSONEncoder`.

## Message Types

### AccessibilityEvent

A tagged union (Swift enum) that serves as the single message type for both directions. The JSON is a single-key object whose key is the case name and whose value is an object containing the associated values (keyed by `_0` for unnamed parameters, or by label for named ones). Cases with no associated values encode as an empty object value.

#### Variant: `requestSnapshot`

**Direction:** Desktop -> Client

Requests the client to capture the current screen and return a `snapshot` event.

##### JSON Schema

```json
{
  "requestSnapshot": {}
}
```

No fields. The client should respond with a `snapshot` event.

---

#### Variant: `sendLiveUpdates`

**Direction:** Desktop -> Client

Tells the client whether to continuously send snapshots as the UI changes.

##### JSON Schema

```json
{
  "sendLiveUpdates": {
    "_0": true
  }
}
```

##### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | boolean | Yes | `true` to enable continuous snapshot updates; `false` to disable them. |

---

#### Variant: `snapshot`

**Direction:** Client -> Desktop

Delivers a captured screenshot and the accessibility elements found on screen.

##### JSON Schema

```json
{
  "snapshot": {
    "_0": {
      "imageData": "<base64-encoded string>",
      "elements": []
    }
  }
}
```

##### Field Reference (Snapshot object at `_0`)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `imageData` | string (base64) | Yes | The screenshot image data, base64-encoded. This is a PNG or similar image format that can be decoded into a displayable bitmap. Swift `Data` encodes to a base64 string under the default `JSONEncoder`. |
| `elements` | array of `AccessibilityElement` | Yes | All accessibility elements found on screen at the time of capture. May be an empty array. |

---

### AccessibilityElement

Describes a single accessibility element on the screen, including its label, identifier, frame, and supported actions.

#### JSON Schema

```json
{
  "description": "string",
  "identifier": "string (optional, absent when nil)",
  "hint": "string (optional, absent when nil)",
  "userInputLabels": ["string"],
  "customActions": ["string"],
  "frame": {
    "x": 0.0,
    "y": 0.0,
    "width": 0.0,
    "height": 0.0
  }
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | The accessibility label read by VoiceOver when the element receives focus. |
| `identifier` | string | No | A unique identifier for the element, primarily used in UI tests. Absent from JSON when `nil`. |
| `hint` | string | No | Additional text read by VoiceOver after the description if focus remains on the element. Absent from JSON when `nil`. |
| `userInputLabels` | array of string | No | Labels used by Voice Control for user input. Absent from JSON when `nil`. |
| `customActions` | array of string | Yes | Names of custom accessibility actions supported by the element. May be an empty array. |
| `frame` | Rect object | Yes | The bounding rectangle of the element in screen coordinates. |

---

### Rect

Describes the position and size of an accessibility element on screen.

#### JSON Schema

```json
{
  "x": 0.0,
  "y": 0.0,
  "width": 0.0,
  "height": 0.0
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `x` | number | Yes | The x-coordinate of the element's origin (top-left corner), in points. |
| `y` | number | Yes | The y-coordinate of the element's origin (top-left corner), in points. |
| `width` | number | Yes | The width of the element, in points. |
| `height` | number | Yes | The height of the element, in points. |

All values are floating-point numbers (`CGFloat` in Swift, encoded as JSON numbers).

## Encoding Notes

1. **Enum encoding format:** `AccessibilityEvent` uses Swift's compiler-synthesized `Codable` for enums with associated values (Swift 5.5+). Each case is encoded as a JSON object with a single key (the case name). The value is another object containing the associated values. Unnamed associated values use positional keys: `_0`, `_1`, etc.

2. **`Data` as base64:** The `imageData` field is Swift `Data`, which the default `JSONEncoder` encodes as a base64-encoded string (no line breaks, standard base64 alphabet with `+` and `/`, `=` padding).

3. **Optional fields are absent, not null:** When an optional field (e.g., `identifier`, `hint`, `userInputLabels`) is `nil`, the key is entirely omitted from the JSON object. It is never encoded as `null`.

4. **PluginConnection encoder:** The `PluginConnection` uses a custom `JSONEncoder` that encodes dates as milliseconds since Unix epoch (1970-01-01). No dates appear in this API, so this has no effect. Key names match property names exactly (no snake_case conversion).

5. **Frame coordinates:** The `Rect` values represent the element's position in the coordinate system of the captured screen, measured in points. The desktop applies its own scaling to map these onto the displayed snapshot image.

## Examples

### Desktop requests a snapshot

The desktop sends this when the user clicks the "Take a Snapshot" button.

```json
{
  "requestSnapshot": {}
}
```

### Desktop enables live updates

Sent when the user toggles "Live Updates" on.

```json
{
  "sendLiveUpdates": {
    "_0": true
  }
}
```

### Desktop disables live updates

```json
{
  "sendLiveUpdates": {
    "_0": false
  }
}
```

### Client sends a snapshot with multiple elements

The client responds with the captured screen image and all discovered accessibility elements.

```json
{
  "snapshot": {
    "_0": {
      "imageData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==",
      "elements": [
        {
          "description": "Submit Order",
          "identifier": "submit_order_button",
          "hint": "Double tap to submit your order",
          "customActions": ["Increment", "Decrement"],
          "frame": {
            "x": 120.0,
            "y": 540.5,
            "width": 200.0,
            "height": 44.0
          }
        },
        {
          "description": "Shopping Cart",
          "customActions": [],
          "frame": {
            "x": 0.0,
            "y": 0.0,
            "width": 393.0,
            "height": 852.0
          }
        }
      ]
    }
  }
}
```

Note in the second element, `identifier`, `hint`, and `userInputLabels` are omitted because they are `nil`.

### Client sends a snapshot with no accessibility elements

```json
{
  "snapshot": {
    "_0": {
      "imageData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==",
      "elements": []
    }
  }
}
```
