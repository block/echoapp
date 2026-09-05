# Logging Plugin API

Displays log messages from the client app in a searchable, filterable table on the desktop, with monospaced font rendering for readability.

## Communication Pattern

**Direction:** Client -> Desktop (unidirectional)

The client sends individual `EchoTableRow` objects over the plugin connection, each representing a single log entry. The desktop plugin does not send any messages back to the client. Each row is appended to the table as it arrives (newest first).

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
| `Time` | Timestamp of the log entry | 100pt-wide column |
| `Level` | Log level (e.g., `"debug"`, `"info"`, `"error"`) | Filterable; 50pt-wide column |
| `Priority` | Log priority | Filterable; 50pt-wide column |
| `Message` | The log message content | 300pt-wide column; used as detail view title |

Additional column keys beyond these are accepted and will appear as extra columns in the table.

## Encoding Notes

1. **All values are strings:** Both keys and values in `columnItems` are strings. Numeric or structured data should be converted to a string representation before sending.

2. **One row per message:** Each JSON message represents a single table row. The client sends one `EchoTableRow` per log entry. Messages are not batched into arrays.

3. **Row ordering:** Rows appear newest-first in the desktop table. The desktop inserts each incoming row at the top.

4. **Row limit:** The desktop keeps a maximum of 2,000 rows in memory. When this limit is exceeded, the oldest rows are discarded.

## Examples

### An error log entry

```json
{
  "id": "c3d4e5f6-a1b2-7890-abcd-1234567890ab",
  "columnItems": {
    "Time": "2024-03-15 14:32:01.234",
    "Level": "error",
    "Priority": "high",
    "Message": "Failed to fetch user profile: HTTP 503 Service Unavailable"
  }
}
```

### A debug log entry

```json
{
  "id": "d4e5f6a1-b2c3-4567-890a-bcdef1234567",
  "columnItems": {
    "Time": "14:32:01.235",
    "Level": "debug",
    "Priority": "low",
    "Message": "Cache hit for key: user_profile_123"
  }
}
```
