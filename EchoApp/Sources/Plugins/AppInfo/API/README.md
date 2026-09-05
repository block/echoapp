# AppInfo Plugin API

Displays key-value application information on the desktop, organized by scope and searchable by the user.

## Communication Pattern

**Direction:** Client -> Desktop (unidirectional)

The client sends a single message containing all application info entries. The desktop plugin does not send any messages back to the client.

## Message Types

### Entry (array)

**Direction:** Client -> Desktop

The client sends a JSON array of `Entry` objects. Each time the array is received, it replaces the previous set of entries entirely.

#### JSON Schema

```json
[
  {
    "scope": "<string>",
    "key": "<string>",
    "value": "<string>"
  }
]
```

#### Field Reference

| Field   | Type   | Required | Description                                                        |
|---------|--------|----------|-------------------------------------------------------------------|
| `scope` | string | Yes      | Logical grouping label (e.g. `"1 - Tokens"`, `"Environment"`).   |
| `key`   | string | Yes      | Property name displayed as the label. Also used as the entry's ID. |
| `value` | string | Yes      | Property value displayed alongside the key.                        |

All three fields are required strings. There are no optional fields, nested objects, or enums in this message type.

## Encoding Notes

- Standard JSON encoding is used; no custom `CodingKeys` or custom `Codable` conformance.
- The `Entry` type has a computed `id` property (`var id: String { key }`) that is **not** encoded in JSON -- it is derived from `key` at decode time.
- The top-level value is a JSON **array**, not a JSON object.
- The array may be empty (`[]`), in which case the desktop plugin shows a null-state / "connect to a device" message.

## Examples

### Typical payload

```json
[
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
```

### Empty state

```json
[]
```

### Minimal single-entry payload

```json
[
  {
    "scope": "General",
    "key": "App Name",
    "value": "My App"
  }
]
```
