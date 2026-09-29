---
title: Client plugins
description: The part of an EchoApp plugin that observes and controls a running mobile app.
section: Concepts
permalink: /concepts/client-plugins/
---

# Client plugins

A client plugin runs inside the app you are debugging. It turns app behavior into a focused API and
exchanges messages with a desktop plugin that has the same identifier.

## What a client plugin does

- Exposes an app-facing API, such as `record(event:)` or `sendSnapshot()`.
- Collects and transforms debug data without coupling application code to the desktop UI.
- Sends serializable messages through its `PluginConnection`.
- Receives commands or state changes from the desktop plugin.
- Releases connection-scoped work when the client disconnects.

On Swift, a plugin conforms to `ClientPlugin` and implements `onConnect` and `onDisconnect`.
Optional hooks report when its desktop view becomes active. On Android, a plugin implements the
`ClientPlugin` interface and receives both a `CoroutineScope` and `PluginConnection` when connected.

## Design guidelines

- Keep the plugin identifier stable and identical on both platforms and the desktop.
- Version the payload contract, especially when old mobile builds may connect to a newer desktop app.
- Keep collection cheap while disconnected and stop connection-scoped work promptly.
- Prefer small event payloads over periodic dumps of a large object graph.
- Make write operations obvious in both the API and desktop UI.
- Never assume debug payloads are safe to publish.

Continue with [Build a plugin](../../guides/build-a-plugin/) for a complete paired example.
