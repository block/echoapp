# Networking Plugin API

Captures and displays HTTP network traffic from the client app. Supports two modes: **Proxy mode** where Echo executes requests on the client's behalf (enabling fixtures, delays, and error simulation), and **Passive mode** where the client executes requests normally while Echo records the traffic.

## Communication Pattern

**Direction:** Bidirectional

- **Client -> Desktop:** `NetworkingPluginClientEvent` — sends requests, finalized responses, and errors.
- **Desktop -> Client:** `NetworkingPluginServerEvent` — sends raw HTTP responses or proposed human-readable responses (proxy mode only).

The client also supports a **deprecated** event format (`DeprecatedNetworkingPluginClientEvent`) for backwards compatibility. The desktop accepts both formats.

### Proxy Mode

```
+---------+       +----------+       +---------+
| Client  |       |  Echo    |       |   Web   |
+---------+       |  Desktop |       +---------+
     |            +----------+           |
     |                 |                 |
     | request(proxy=true)               |
     |---------------->|                 |
     |                 |  HTTP Request   |
     |                 |---------------->|
     |                 |  HTTP Response  |
     |                 |<----------------|
     | serverEvent     |                 |
     |<----------------|                 |
     | finalizedResponse                 |
     |---------------->|                 |
```

1. Client sends `.request` with `proxy: true` and **pauses execution**.
2. Echo Desktop executes the HTTP request (or returns a fixture/simulated error).
3. Echo Desktop sends a `NetworkingPluginServerEvent` back to the client.
4. Client processes the response and sends `.finalizedResponse`.

### Passive Mode

```
+---------+       +----------+       +---------+
| Client  |       |  Echo    |       |   Web   |
+---------+       |  Desktop |       +---------+
     |            +----------+           |
     |                 |                 |
     | request(proxy=false)              |
     |---------------->|                 |
     |  HTTP Request   |                 |
     |----------------------------------->|
     |  HTTP Response  |                 |
     |<-----------------------------------|
     | finalizedResponse                 |
     |---------------->|                 |
```

1. Client sends `.request` with `proxy: false` to notify Echo.
2. Client executes the HTTP request independently.
3. Client sends `.finalizedResponse` when done.

In both modes, the client must **always** send `.finalizedResponse` to complete the request lifecycle.

## Message Types

### NetworkingPluginClientEvent

**Direction:** Client -> Desktop

A tagged union whose JSON is a single-key object. The key is the variant name and the value is an object containing the variant's fields.

---

#### Variant: `request`

Notifies Echo that the client is making a network request.

```json
{
  "request": {
    "_0": <Request>,
    "proxy": true
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | Request | Yes | The HTTP request details. |
| `proxy` | boolean | Yes | `true` for proxy mode (Echo executes the request); `false` for passive mode (client executes). |

---

#### Variant: `finalizedResponse`

Sends the final human-readable response after the request completes. Must be sent for every request regardless of mode.

```json
{
  "finalizedResponse": {
    "_0": <HumanReadableResponse>
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | HumanReadableResponse | Yes | The final response with a human-readable body (e.g., JSON string, not binary). |

---

#### Variant: `error`

Reports an error encountered by the client.

```json
{
  "error": {
    "_0": <Error>,
    "requestID": "abc-123"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | Error | Yes | The error details (see Error type below). |
| `requestID` | string | Yes | ID of the request that caused the error. |

##### Error

A tagged union with one variant:

**`failedToParseProposedHumanReadableResponse`** — Echo sent a human-readable response (e.g., a fixture) that the client could not convert to its expected format (e.g., protobuf).

```json
{
  "failedToParseProposedHumanReadableResponse": {
    "reason": "Could not deserialize JSON to protobuf: missing required field 'user_id'"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | Yes | Human-readable explanation of the parse failure. |

---

### NetworkingPluginServerEvent

**Direction:** Desktop -> Client (proxy mode only)

A tagged union sent by Echo Desktop when responding to a proxied request.

---

#### Variant: `rawResponse`

Echo proxied the request and returns the raw HTTP response.

```json
{
  "rawResponse": {
    "_0": <RawResponse>
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | RawResponse | Yes | The HTTP response with a raw (possibly binary) body. |

---

#### Variant: `proposedHumanReadableResponse`

Echo provides a human-readable response (typically a fixture or modified response).

```json
{
  "proposedHumanReadableResponse": {
    "_0": <HumanReadableResponse>
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `_0` | HumanReadableResponse | Yes | The proposed response with a human-readable body. The client should attempt to parse and use it, sending `.error` if parsing fails. |

---

### Request

Describes an outgoing HTTP request.

#### JSON Schema

```json
{
  "id": "abc-123",
  "url": "https://api.example.com/v1/users",
  "httpMethod": "GET",
  "headers": {
    "Authorization": "Bearer token123",
    "Content-Type": "application/json"
  },
  "timestamp": 1710512000000,
  "humanReadableBody": "{\"name\": \"John\"}",
  "rawBody": "eyJuYW1lIjogIkpvaG4ifQ=="
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier for this request. Used to correlate with responses. |
| `url` | string | Yes | The full request URL including scheme, host, path, and query string. |
| `httpMethod` | string | Yes | HTTP method (e.g., `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`). |
| `headers` | object (string keys, string values) | Yes | HTTP request headers. May be empty. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch (1970-01-01 00:00:00 UTC). |
| `humanReadableBody` | string | Yes | The request body in a human-readable format (e.g., JSON string). Empty string if no body. |
| `rawBody` | string (base64) | No | The raw request body, base64-encoded. Absent when there is no raw body. |

Note: The `endpoint` computed property is not included in the JSON encoding.

---

### Response (HumanReadableResponse / RawResponse)

Describes an HTTP response. This is a generic type parameterized by the body type:
- **HumanReadableResponse** (`Response<String>`): Body is a JSON string.
- **RawResponse** (`Response<Data?>`): Body is base64-encoded binary data (or absent when nil).

#### JSON Schema (HumanReadableResponse)

```json
{
  "requestID": "abc-123",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"id\": 1, \"name\": \"John\"}",
  "statusCode": 200
}
```

#### JSON Schema (RawResponse)

```json
{
  "requestID": "abc-123",
  "headers": {
    "Content-Type": "application/octet-stream"
  },
  "body": "eyJpZCI6IDEsICJuYW1lIjogIkpvaG4ifQ==",
  "statusCode": 200
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `requestID` | string | Yes | Matches the `id` of the corresponding Request. |
| `headers` | object (string keys, string values) | Yes | HTTP response headers. May be empty. |
| `body` | string | Yes* | For HumanReadableResponse: a human-readable string (e.g., formatted JSON). For RawResponse: base64-encoded data, or absent when nil. |
| `statusCode` | number (integer) | Yes | HTTP status code (e.g., `200`, `404`, `500`). |

*For RawResponse, `body` may be absent when the response has no body.

---

### DeprecatedNetworkingPluginClientEvent (Legacy)

An older event format still supported for backwards compatibility. The desktop automatically translates these into modern `NetworkingPluginClientEvent` messages (with `proxy: false`).

---

#### Variant: `request`

```json
{
  "request": {
    "_0": {
      "id": "abc-123",
      "endpoint": { "path": "/v1/users" },
      "httpMethod": "GET",
      "headers": {},
      "timestamp": 1710512000000,
      "queryParameters": { "page": "1" },
      "humanReadableBody": ""
    }
  }
}
```

**Deprecated Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique request identifier. |
| `endpoint` | Endpoint | Yes | Path-only endpoint (see Endpoint below). |
| `httpMethod` | string | Yes | HTTP method. |
| `headers` | object (string keys, string values) | Yes | Request headers. |
| `timestamp` | number | Yes | Milliseconds since Unix epoch. |
| `queryParameters` | object (string keys, string values) | Yes | URL query parameters as key-value pairs. |
| `humanReadableBody` | string | Yes | Human-readable request body. |

---

#### Variant: `response`

```json
{
  "response": {
    "_0": {
      "requestID": "abc-123",
      "headers": { "Content-Type": "application/json" },
      "humanReadableBody": "{\"id\": 1}",
      "statusCode": 200
    }
  }
}
```

**Deprecated Response fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `requestID` | string | Yes | Matches the request `id`. |
| `headers` | object (string keys, string values) | Yes | Response headers. |
| `humanReadableBody` | string | Yes | Human-readable response body. |
| `statusCode` | number (integer) | Yes | HTTP status code. |

---

### Endpoint

Describes a URL path, used in the deprecated event format.

#### JSON Schema

```json
{
  "path": "/v1/users"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | Yes | Normalized URL path with a leading slash and no trailing slashes. Supports `*` wildcards for single path component matching. |

## Encoding Notes

1. **Tagged union format:** All event enums use Swift's compiler-synthesized `Codable` for enums with associated values (Swift 5.5+). Each case is a JSON object with a single key (the case name). Unnamed parameters use positional keys (`_0`, `_1`, etc.); named parameters use their label.

2. **Date encoding:** All `Date` values are encoded as **integers representing milliseconds since Unix epoch** (1970-01-01 00:00:00 UTC). The `PluginConnection` uses a custom encoder: `Int(date.timeIntervalSince1970 * 1000)`.

3. **URL encoding:** `URL` values are encoded as strings (the absolute URL).

4. **Data encoding:** `Data` values (e.g., `rawBody`) are encoded as base64 strings (standard alphabet, `=` padding, no line breaks).

5. **Optional fields are absent, not null:** When an optional field is `nil`, the key is omitted from the JSON. It is never encoded as `null`.

6. **Dual event format support:** The desktop accepts both `NetworkingPluginClientEvent` (modern) and `DeprecatedNetworkingPluginClientEvent` (legacy). Clients should use the modern format. The deprecated format is translated to modern events with `proxy: false`.

7. **Ambiguous `request` key:** Both the modern and deprecated client events have a `request` variant, but they have different payload shapes. The modern one has `_0` (Request) + `proxy` (Bool); the deprecated one has `_0` (DeprecatedRequest with different fields). The desktop listens for both types independently on the connection.

## Examples

### Client sends a proxy request

```json
{
  "request": {
    "_0": {
      "id": "req-001",
      "url": "https://api.example.com/v2/users/123",
      "httpMethod": "GET",
      "headers": {
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9...",
        "Accept": "application/json"
      },
      "timestamp": 1710512000000,
      "humanReadableBody": ""
    },
    "proxy": true
  }
}
```

### Echo Desktop returns a raw response (proxy mode)

```json
{
  "rawResponse": {
    "_0": {
      "requestID": "req-001",
      "headers": {
        "Content-Type": "application/json",
        "X-Request-Id": "srv-abc-123"
      },
      "body": "eyJpZCI6IDEyMywgIm5hbWUiOiAiSm9obiJ9",
      "statusCode": 200
    }
  }
}
```

### Client sends finalized response

```json
{
  "finalizedResponse": {
    "_0": {
      "requestID": "req-001",
      "headers": {
        "Content-Type": "application/json"
      },
      "body": "{\"id\": 123, \"name\": \"John\"}",
      "statusCode": 200
    }
  }
}
```

### Client sends a passive request

```json
{
  "request": {
    "_0": {
      "id": "req-002",
      "url": "https://api.example.com/v2/feed",
      "httpMethod": "POST",
      "headers": {
        "Content-Type": "application/json"
      },
      "timestamp": 1710512010000,
      "humanReadableBody": "{\"cursor\": \"abc123\", \"limit\": 20}",
      "rawBody": "eyJjdXJzb3IiOiAiYWJjMTIzIiwgImxpbWl0IjogMjB9"
    },
    "proxy": false
  }
}
```

### Client reports a parse error

```json
{
  "error": {
    "_0": {
      "failedToParseProposedHumanReadableResponse": {
        "reason": "Could not deserialize JSON to protobuf: missing required field 'user_id'"
      }
    },
    "requestID": "req-001"
  }
}
```

### Legacy client sends a request (deprecated format)

```json
{
  "request": {
    "_0": {
      "id": "legacy-req-001",
      "endpoint": { "path": "/v1/example/get-profile" },
      "httpMethod": "GET",
      "headers": { "Authorization": "Bearer token" },
      "timestamp": 1710512000000,
      "queryParameters": { "include_balance": "true" },
      "humanReadableBody": ""
    }
  }
}
```
