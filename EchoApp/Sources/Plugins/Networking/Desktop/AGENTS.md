# Networking Plugin (Network Monitor)

## Overview

The Networking plugin captures HTTP network traffic from connected iOS/Android apps. It is the most important plugin for AI agents debugging app behavior.

- **Plugin ID:** `com.echo.plugin.network`
- **Sanitized name:** `network` (used in filenames and CLI commands)
- **Data file:** `network.jsonl` in the session directory

Two operating modes:
- **Proxy mode:** The app sends requests to Echo, which executes them (or returns fixtures) and sends responses back. Enables fixtures, delays, and error simulation.
- **Passive mode:** The app executes requests normally and reports traffic to Echo for observation only.

## Data Format

Each line in `network.jsonl` is a JSON object written by `CLISessionWriter`. The `data` field contains the raw plugin event (request, finalizedResponse, or error).

### Example: Request entry

```json
{"timestamp":"2025-04-03T10:15:30Z","plugin_id":"network","data":{"request":{"_0":{"id":"req-001","url":"https://api.example.com/2.0/example/get-profile","httpMethod":"GET","headers":{"Authorization":"Bearer token123","Content-Type":"application/json"},"timestamp":1710512000000,"humanReadableBody":""},"proxy":true}}}
```

### Example: Finalized response entry

```json
{"timestamp":"2025-04-03T10:15:31Z","plugin_id":"network","data":{"finalizedResponse":{"_0":{"requestID":"req-001","headers":{"Content-Type":"application/json"},"body":"{\"id\": 123, \"name\": \"John\"}","statusCode":200}}}}
```

### Key fields in request data

| Field | Description |
|-------|-------------|
| `id` | Unique request ID (used to correlate with responses) |
| `url` | Full URL including scheme, host, path, and query string |
| `httpMethod` | `GET`, `POST`, `PUT`, `DELETE`, etc. |
| `headers` | Request headers as key-value pairs |
| `timestamp` | Milliseconds since Unix epoch |
| `humanReadableBody` | Request body as readable string (empty if none) |
| `rawBody` | Base64-encoded raw body (optional) |

### Key fields in response data

| Field | Description |
|-------|-------------|
| `requestID` | Matches the request `id` |
| `headers` | Response headers |
| `body` | Response body as readable string |
| `statusCode` | HTTP status code (200, 404, 500, etc.) |

## Querying Data

Use `echoapp query network` with filters:

```bash
# All network traffic (last 50 entries)
echoapp query network

# Filter by URL substring
echoapp query network --url /get-profile

# Filter by HTTP method
echoapp query network --method POST

# Filter by status code
echoapp query network --status 500

# Recent traffic only
echoapp query network --last 5m

# Combine filters
echoapp query network --url /payments --method POST --status 200 --last 10m

# More results
echoapp query network --limit 200

# Compact output
echoapp query network --format compact
```

### Tail live traffic

```bash
# Follow new entries in real time
echoapp tail network -f

# Show last 20 entries then follow
echoapp tail network -f --lines 20
```

## Proxy Mode

When the connected app uses `EchoURLProtocol` (proxy mode), `echoapp` transparently executes HTTP requests on behalf of the app. The proxy:

1. Receives the request from the app via WebSocket
2. Checks for matching fixtures first
3. If no fixture matches, forwards the request to the real server
4. Returns the response to the app

You will see `Proxy mode detected -- echoapp will forward network requests.` in stderr when proxy mode activates. This is automatic and requires no agent action.

## Fixtures

Fixtures let you intercept network requests and return custom responses during a live session. When a proxy-mode request matches a fixture's endpoint path, echoapp returns the fixture instead of forwarding to the real server.

### Adding a fixture

```bash
# Basic fixture with inline JSON body
echoapp fixture add /2.0/example/get-profile --body '{"name": "Test User", "balance": 100}'

# Custom status code (e.g., simulate server error)
echoapp fixture add /2.0/example/initiate-payment --body '{}' --status-code 500

# Read body from a file
echoapp fixture add /2.0/example/get-profile --body-file ./mock-profile.json

# Named fixture (allows multiple per endpoint; first alphabetically wins)
echoapp fixture add /2.0/example/get-profile --name error --body '{"error": "not_found"}' --status-code 404
```

### Listing fixtures

```bash
echoapp fixture list
echoapp fixture list --format json
```

### Removing fixtures

```bash
# Remove all fixtures for an endpoint
echoapp fixture remove /2.0/example/get-profile

# Remove a specific named fixture
echoapp fixture remove /2.0/example/get-profile --name error

# Remove all fixtures
echoapp fixture remove --all
```

### Fixture file format

Fixture files are JSON stored at `$ECHO_DATA_DIR/current/fixtures/<endpoint-path>/<name>.json`:

```json
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json"
    },
    "body": "{\"key\": \"value\"}"
}
```

### Fixture behavior

- **Session-scoped:** Fixtures only apply to the current session and are discarded when it ends.
- **Path matching:** Endpoints are matched by normalized URL path. `/2.0/example/get-profile` matches requests to any host with that path, regardless of query parameters or HTTP method.
- **Priority:** If multiple fixture files exist for the same endpoint, the first alphabetically by filename is used.
- **Logging:** When a fixture matches, stderr shows: `[FIXTURE] /2.0/example/get-profile -> fixture.json (200)`

## MCP Tools

If using the Echo MCP server (port 34001) instead of echoapp, these tools are available:

| Tool | Description |
|------|-------------|
| `list_exchanges` | List captured packets with filters: `url`, `method`, `status_code`, `last_seconds`, `since`, `limit`, `offset` |
| `get_exchange` | Full details of one packet (request headers/body, response headers/body, status) |
| `search_exchanges` | Search packets by URL substring |
| `clear_exchanges` | Clear all captured packets |

## Common Agent Workflows

### Inspect API responses for a specific endpoint

```bash
echoapp query network --url /2.0/example/get-profile --limit 5
```

Look at the `data.finalizedResponse._0.body` and `data.finalizedResponse._0.statusCode` fields in the output.

### Mock an endpoint to test UI behavior

```bash
# 1. Add a fixture with the desired response
echoapp fixture add /2.0/example/get-profile --body '{"name": "Test", "balance": 0}'

# 2. Trigger the action in the app (navigate, pull-to-refresh, etc.)
# 3. Verify the fixture was served
echoapp query network --url /get-profile --last 30s

# 4. Clean up when done
echoapp fixture remove /2.0/example/get-profile
```

### Check if a specific API call was made

```bash
# Check for any calls to a specific endpoint
echoapp query network --url /initiate-payment --last 2m

# Check for specific method + endpoint
echoapp query network --url /initiate-payment --method POST --last 2m
```

### Find error responses

```bash
# Find 500 errors
echoapp query network --status 500

# Find 4xx client errors
echoapp query network --status 401
echoapp query network --status 404

# Watch for errors in real time
echoapp tail network -f
```

### Simulate error states

```bash
# Return 500 for a critical endpoint
echoapp fixture add /2.0/example/get-balance --body '{"error": "internal"}' --status-code 500

# Return 401 to test auth flow
echoapp fixture add /2.0/example/get-profile --body '{"error": "unauthorized"}' --status-code 401

# Clean up all fixtures after testing
echoapp fixture remove --all
```
