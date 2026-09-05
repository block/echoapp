# Analytics Plugin API

Displays analytics events from the client app in a searchable, filterable table on the desktop.

## Communication Pattern

**Direction:** Client -> Desktop (unidirectional)

The client sends individual `EchoTableRow` objects over the plugin connection, each representing a single analytics event. The desktop plugin does not send any messages back to the client. Each row is appended to the table as it arrives (newest first).

## Message Types

### EchoTableRow

**Direction:** Client -> Desktop

A single row of tabular data. Each row has a unique identifier and a dictionary of column name/value pairs.

#### JSON Schema

```json
{
  "id": "<string>",
  "columnItems": {
    "<column_name>": "<value>"
  }
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier for the row. Typically a UUID string (e.g., `"550e8400-e29b-41d4-a716-446655440000"`). |
| `columnItems` | object (string keys, string values) | Yes | Key-value pairs where each key is a column name and each value is the display text for that column. |

#### Expected Column Keys

The desktop plugin is configured to display these columns (in order):

| Column Key | Description | Notes |
|-----------|-------------|-------|
| `Time` | Timestamp of the analytics event | 100pt-wide column |
| `Source` | Origin or source of the event | Filterable; 80pt-wide column |
| `Event` | Name of the analytics event | Filterable; 300pt-wide column |
| `Raw Message` | The raw message or payload | Hidden by default; visible in detail view |
| `Properties` | Event properties/metadata | Hidden by default; visible in detail view |

Additional column keys beyond these are accepted and will appear as extra columns in the table.

## Encoding Notes

1. **All values are strings:** Both keys and values in `columnItems` are strings. Numeric or structured data should be converted to a string representation before sending.

2. **One row per message:** Each JSON message represents a single table row. The client sends one `EchoTableRow` per analytics event. Messages are not batched into arrays.

3. **Row ordering:** Rows appear oldest-first in the desktop table. The desktop appends each incoming row to the bottom.

4. **Row limit:** The desktop keeps a maximum of 2,000 rows in memory. When this limit is exceeded, the oldest rows are discarded.

## Examples

### A single analytics event

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "columnItems": {
    "Time": "2024-03-15 14:32:01",
    "Source": "Analytics",
    "Event": "AppNavigate",
    "Raw Message": "{\"screen\":\"home\",\"source\":\"tab_bar\"}",
    "Properties": "screen=home, source=tab_bar"
  }
}
```

### Minimal event

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "columnItems": {
    "Time": "14:32:01",
    "Event": "ButtonTapped"
  }
}
```
