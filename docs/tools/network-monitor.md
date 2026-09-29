---
title: Network Monitor
description: Inspect live HTTP traffic and replace selected responses with development fixtures.
section: Tools
permalink: /tools/network-monitor/
---

# Network Monitor

Network Monitor shows requests and responses observed by the client networking plugin. Use it to
search traffic, inspect headers and bodies, reproduce error states, and serve local fixtures without
changing your backend.

## Capture requests

1. Register the networking client plugin or interceptor in your development app.
2. Start the client and connect it from EchoApp.
3. Open **Network Monitor** in the EchoApp sidebar.
4. Exercise the app. New exchanges appear as they complete.

Select a row to inspect its request and response. Search matches request metadata and payload text;
column filters narrow by fields such as method or status.

<div class="callout callout-warning">
  <strong>Captured traffic can contain secrets.</strong> Redact authorization headers, cookies,
  personal data, and account identifiers before sharing a request or pasting it into an AI prompt.
</div>

## Mock an error response

Open the **Rules** view, add the URL path you want to intercept, and choose a response. Common HTTP
statuses are available directly. Use a custom response when you need a different status, headers,
delay, or body.

Match the narrowest useful path. A rule for `/api/v1/profile` is easier to reason about than a rule
that catches every `/api/` request.

## Serve a JSON fixture

The rules view shows the active fixture directory. Mirror an endpoint's path, then add one or more
named JSON files:

```text
Fixtures/
└── api/
    └── v1/
        └── profile/
            ├── default.json
            ├── empty.json
            └── server-error.json
```

Return to the rule and select the fixture by name. Keep fixtures small, deterministic, and free of
real customer data. Commit reusable fixtures alongside the app or test suite that owns the API
contract—not to a personal Application Support directory.

## Control fixtures from the CLI

An active `echoapp connect` session can install and remove fixtures without opening the GUI:

```sh
echoapp fixture add /api/v1/profile --body-file Fixtures/api/v1/profile/empty.json
echoapp fixture list
echoapp fixture remove /api/v1/profile
```

Run `echoapp fixture --help` for delay, status-code, and named-fixture options. This is useful for
repeatable tests that establish a response, drive the app, assert behavior, and clean up.

## Client instrumentation

The Swift `EchoClient` exposes a networking plugin instance. Android includes OkHttp integration in
the plugin API. In both cases, install the hook only in development configurations and ensure the
plugin instance registered with EchoClient is the same instance receiving network events.

For headless inspection and filtering, continue with the [command-line interface](../cli/).
