# KeyValueStore Plugin API

Provides a bidirectional interface for inspecting and editing key-value stores (e.g., UserDefaults, shared preferences) on the client device. The desktop displays store contents with search, filtering, and inline editing, while supporting conflict resolution for concurrent changes.

## Communication Pattern

**Direction:** Bidirectional

- **Client -> Desktop:** `EchoKeyValueStoreClientEvent` — sends snapshots of all stores, error reports, change confirmations, and conflict notifications.
- **Desktop -> Client:** `EchoKeyValueStoreDesktopEvent` — requests snapshots, and sends update/delete/add commands for individual keys.

All messages are JSON-encoded instances of the respective event enum, transported as the `data` field within an Echo `PluginPayload`.

## Message Types

### EchoKeyValueStoreClientEvent

**Direction:** Client -> Desktop

A tagged union whose JSON is a single-key object. The key is the variant name and the value is an object containing the variant's fields.

---

#### Variant: `updateSnapshot`

Sends a full snapshot of all key-value stores. The desktop performs diffing against its previous state to determine what changed and provide visual feedback.

```json
{
  "updateSnapshot": {
    "_0": <EchoKeyValueStoreSnapshot>
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | EchoKeyValueStoreSnapshot | Yes | Complete snapshot of all stores. |

---

#### Variant: `error`

Reports an error that occurred on the client.

```json
{
  "error": {
    "storeId": "com.example.defaults",
    "message": "Failed to read store"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `storeId` | string | No | ID of the affected store. Absent when the error is not store-specific. |
| `message` | string | Yes | Human-readable error description. |

---

#### Variant: `changeConfirmation`

Confirms whether a desktop-initiated change was applied successfully.

```json
{
  "changeConfirmation": {
    "changeId": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": 1710512000000,
    "success": true
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `changeId` | string (UUID) | Yes | Matches the `changeId` from the original desktop command. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch (1970-01-01 00:00:00 UTC). |
| `success` | boolean | Yes | `true` if the change was applied; `false` if it failed. |

---

#### Variant: `changeConflict`

Reports that a desktop-initiated change was rejected because the value was concurrently modified by the app.

```json
{
  "changeConflict": {
    "changeId": "550e8400-e29b-41d4-a716-446655440000",
    "key": "theme",
    "appValue": { "string": { "_0": "dark" } },
    "desktopValue": { "string": { "_0": "light" } },
    "appTimestamp": 1710512001000,
    "desktopTimestamp": 1710512000000
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `changeId` | string (UUID) | Yes | Matches the `changeId` from the original desktop command. |
| `key` | string | Yes | The key that had a conflict. |
| `appValue` | EchoCodableValue | Yes | The value the app set (winning value). |
| `desktopValue` | EchoCodableValue | Yes | The value the desktop tried to set (rejected value). |
| `appTimestamp` | number | Yes | Milliseconds since Unix epoch when the app made its change. |
| `desktopTimestamp` | number | Yes | Milliseconds since Unix epoch when the desktop made its change. |

---

### EchoKeyValueStoreDesktopEvent

**Direction:** Desktop -> Client

A tagged union with the same encoding pattern as the client event.

---

#### Variant: `requestSnapshot`

Asks the client to send the current state of all stores.

```json
{
  "requestSnapshot": {}
}
```

No fields.

---

#### Variant: `updateValue`

Requests the client to update an existing key's value.

```json
{
  "updateValue": {
    "changeId": "550e8400-e29b-41d4-a716-446655440000",
    "storeId": "com.example.defaults",
    "key": "theme",
    "newValue": { "string": { "_0": "dark" } },
    "type": "string",
    "timestamp": 1710512000000
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `changeId` | string (UUID) | Yes | Unique identifier for this change, used in confirmations and conflict reports. |
| `storeId` | string | Yes | ID of the target store. |
| `key` | string | Yes | The key to update. |
| `newValue` | EchoCodableValue | Yes | The new value to set. |
| `type` | string (EchoKeyValueType) | Yes | The value type (see EchoKeyValueType below). |
| `timestamp` | number | Yes | Milliseconds since Unix epoch. |

---

#### Variant: `deleteKey`

Requests the client to delete a key from a store.

```json
{
  "deleteKey": {
    "changeId": "550e8400-e29b-41d4-a716-446655440000",
    "storeId": "com.example.defaults",
    "key": "deprecated_flag",
    "timestamp": 1710512000000
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `changeId` | string (UUID) | Yes | Unique identifier for this change. |
| `storeId` | string | Yes | ID of the target store. |
| `key` | string | Yes | The key to delete. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch. |

---

#### Variant: `addKey`

Requests the client to add a new key to a store.

```json
{
  "addKey": {
    "changeId": "550e8400-e29b-41d4-a716-446655440000",
    "storeId": "com.example.defaults",
    "key": "new_feature_flag",
    "value": { "boolean": { "_0": true } },
    "type": "boolean",
    "timestamp": 1710512000000
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `changeId` | string (UUID) | Yes | Unique identifier for this change. |
| `storeId` | string | Yes | ID of the target store. |
| `key` | string | Yes | The key to add. |
| `value` | EchoCodableValue | Yes | The value to set. |
| `type` | string (EchoKeyValueType) | Yes | The value type. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch. |

---

#### Variant: `requestFullRefresh`

Requests the client to resync all stores from scratch.

```json
{
  "requestFullRefresh": {}
}
```

No fields.

---

### EchoKeyValueStoreSnapshot

A complete snapshot of all key-value stores at a point in time.

#### JSON Schema

```json
{
  "stores": [<EchoKeyValueStore>],
  "timestamp": 1710512000000
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `stores` | array of EchoKeyValueStore | Yes | All key-value stores. May be empty. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch when the snapshot was captured. |

---

### EchoKeyValueStore

A collection of key-value entries representing a single store (e.g., a UserDefaults suite).

#### JSON Schema

```json
{
  "id": "com.example.defaults",
  "name": "Standard Defaults",
  "sfSymbol": "gearshape.fill",
  "entries": [<EchoKeyValueEntry>],
  "isReadOnly": false,
  "lastUpdated": 1710512000000,
  "supportedTypes": ["string", "integer", "boolean"]
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier for this store. |
| `name` | string | Yes | Human-readable display name. |
| `sfSymbol` | string | Yes | SF Symbol name for the store icon (e.g., `"gearshape.fill"`). |
| `entries` | array of EchoKeyValueEntry | Yes | All entries in this store. May be empty. |
| `isReadOnly` | boolean | Yes | `true` if the store cannot be modified from the desktop. |
| `lastUpdated` | number | Yes | Milliseconds since Unix epoch when the store was last updated. |
| `supportedTypes` | array of string | Yes | EchoKeyValueType values this store supports. May be empty (desktop falls back to all types). |

---

### EchoKeyValueEntry

A single key-value pair within a store.

#### JSON Schema

```json
{
  "key": "theme",
  "value": { "string": { "_0": "dark" } },
  "type": "string",
  "isEditable": true,
  "lastModified": 1710512000000,
  "modificationHistory": []
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | Yes | The key name. Also serves as the entry's unique identifier within its store. |
| `value` | EchoCodableValue | Yes | The current value. |
| `type` | string (EchoKeyValueType) | Yes | The value type. |
| `isEditable` | boolean | Yes | `true` if this entry can be modified from the desktop. |
| `lastModified` | number | No | Milliseconds since Unix epoch. Absent when unknown. |
| `modificationHistory` | array of EchoValueModification | Yes | History of changes to this entry. May be empty. |

---

### EchoValueModification

Records a single change to a value over time.

#### JSON Schema

```json
{
  "timestamp": 1710512000000,
  "oldValue": { "string": { "_0": "light" } },
  "newValue": { "string": { "_0": "dark" } },
  "source": "App",
  "changeDescription": "User changed theme preference",
  "changeId": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | number | Yes | Milliseconds since Unix epoch when the change occurred. |
| `oldValue` | EchoCodableValue | No | Previous value. Absent when unknown or for new entries. |
| `newValue` | EchoCodableValue | Yes | The value after the change. |
| `source` | string | Yes | One of: `"App"`, `"Echo Desktop"`, `"System"`, `"Unknown"`. |
| `changeDescription` | string | Yes | Human-readable description of the change. |
| `changeId` | string (UUID) | No | Links this modification to a desktop-initiated change. Absent for app-initiated changes. |

Note: The `id` property (a UUID) is not encoded in JSON — it is generated at decode time.

---

### EchoCodableValue

A type-safe value wrapper. Encoded as a tagged union where the key indicates the type and `_0` holds the value.

#### Variants

| Variant | JSON | Value Type | Description |
|---------|------|-----------|-------------|
| `string` | `{ "string": { "_0": "hello" } }` | string | A text value. |
| `integer` | `{ "integer": { "_0": 42 } }` | number (32-bit integer) | A 32-bit integer. |
| `integer16` | `{ "integer16": { "_0": 42 } }` | number (16-bit integer) | A 16-bit integer. |
| `integer64` | `{ "integer64": { "_0": 42 } }` | number (64-bit integer) | A 64-bit integer. |
| `float` | `{ "float": { "_0": 3.14 } }` | number | A single-precision float. |
| `double` | `{ "double": { "_0": 3.14159 } }` | number | A double-precision float. |
| `boolean` | `{ "boolean": { "_0": true } }` | boolean | A boolean value. |
| `data` | `{ "data": { "_0": "SGVsbG8=" } }` | string (base64) | Raw binary data, base64-encoded. |
| `date` | `{ "date": { "_0": 1710512000000 } }` | number | Milliseconds since Unix epoch. |
| `array` | `{ "array": { "_0": [...] } }` | array of EchoCodableValue | A nested array of values. |
| `dictionary` | `{ "dictionary": { "_0": { "k": ... } } }` | object (string keys, EchoCodableValue values) | A nested dictionary. |
| `url` | `{ "url": { "_0": "https://example.com" } }` | string | A URL string. |
| `null` | `{ "null": {} }` | (none) | Represents an explicit null/nil value. |

---

### EchoKeyValueType

A string enum indicating the type of a value. Used in `EchoKeyValueEntry.type` and in desktop commands.

| Value | Description |
|-------|-------------|
| `"string"` | String |
| `"integer"` | 32-bit integer |
| `"integer16"` | 16-bit integer |
| `"integer64"` | 64-bit integer |
| `"float"` | Single-precision float |
| `"double"` | Double-precision float |
| `"boolean"` | Boolean |
| `"data"` | Binary data |
| `"date"` | Date |
| `"array"` | Array |
| `"dictionary"` | Dictionary |
| `"url"` | URL |
| `"unknown"` | Unknown/unsupported type |

## Encoding Notes

1. **Tagged union format:** Both event enums and `EchoCodableValue` use Swift's compiler-synthesized `Codable` for enums with associated values (Swift 5.5+). Each case is encoded as a JSON object with a single key (the case name). The value is another object with the associated values. Unnamed parameters use positional keys (`_0`, `_1`, etc.); named parameters use their label as the key.

2. **Date encoding:** All `Date` values are encoded as **integers representing milliseconds since Unix epoch** (1970-01-01 00:00:00 UTC). This applies to all timestamp fields throughout the API. This is NOT Swift's default date encoding — the `PluginConnection` uses a custom encoder that converts dates to `Int(date.timeIntervalSince1970 * 1000)`.

3. **UUID encoding:** UUID values are encoded as lowercase hyphenated strings (e.g., `"550e8400-e29b-41d4-a716-446655440000"`).

4. **Optional fields are absent, not null:** When an optional field (e.g., `lastModified`, `oldValue`, `storeId`, `changeId`) is nil, the key is entirely omitted from the JSON object. It is never encoded as JSON `null`. Note that `EchoCodableValue.null` is a distinct concept — it represents an explicit null value in the key-value store, not a missing JSON field.

5. **Excluded computed properties:** Several types have computed properties (`id` on `EchoKeyValueEntry`, `id` on `EchoValueModification`, `displayValue`, `formattedType`, `supportedTypesOrDefault`) that are NOT included in the JSON encoding.

## Examples

### Client sends a snapshot with one store

```json
{
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
```

### Desktop requests a snapshot

```json
{
  "requestSnapshot": {}
}
```

### Desktop updates a value

```json
{
  "updateValue": {
    "changeId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "storeId": "com.example.app.defaults",
    "key": "theme",
    "newValue": { "string": { "_0": "light" } },
    "type": "string",
    "timestamp": 1710512005000
  }
}
```

### Client confirms a change

```json
{
  "changeConfirmation": {
    "changeId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "timestamp": 1710512005100,
    "success": true
  }
}
```

### Client reports a conflict

```json
{
  "changeConflict": {
    "changeId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "key": "theme",
    "appValue": { "string": { "_0": "blue" } },
    "desktopValue": { "string": { "_0": "light" } },
    "appTimestamp": 1710512004500,
    "desktopTimestamp": 1710512005000
  }
}
```

### Desktop deletes a key

```json
{
  "deleteKey": {
    "changeId": "b2c3d4e5-f6a1-2345-6789-0abcdef12345",
    "storeId": "com.example.app.defaults",
    "key": "deprecated_flag",
    "timestamp": 1710512010000
  }
}
```

### Desktop adds a new key

```json
{
  "addKey": {
    "changeId": "c3d4e5f6-a1b2-3456-7890-abcdef123456",
    "storeId": "com.example.app.defaults",
    "key": "new_feature_enabled",
    "value": { "boolean": { "_0": false } },
    "type": "boolean",
    "timestamp": 1710512015000
  }
}
```

### Client reports an error

```json
{
  "error": {
    "storeId": "com.example.app.defaults",
    "message": "Permission denied: cannot read store"
  }
}
```

### Client reports an error without a store ID

```json
{
  "error": {
    "message": "Connection timeout"
  }
}
```
