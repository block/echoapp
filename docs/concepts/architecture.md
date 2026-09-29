---
title: Architecture
description: How EchoApp connects a desktop host to independent client and desktop plugin pairs.
section: Concepts
permalink: /concepts/architecture/
---

# Architecture

EchoApp deliberately keeps the host small. It establishes a connection to a client, discovers the
plugins supported by that client, and loads the corresponding desktop plugins. Everything specific
to a debugging tool stays inside its plugin pair.

## The plugin pair

<div class="architecture" role="img" aria-label="A client plugin and desktop plugin exchange messages through the EchoApp transport">
  <div class="architecture-node">
    <strong>Client plugin</strong>
    <span>Runs inside your iOS or Android development build. Observes app behavior and exposes safe debug controls.</span>
  </div>
  <div class="architecture-link"><b aria-hidden="true">⇄</b><span>JSON over WebSocket</span></div>
  <div class="architecture-node">
    <strong>Desktop plugin</strong>
    <span>Runs inside EchoApp on macOS. Decodes messages, stores view state, and renders a native SwiftUI interface.</span>
  </div>
</div>

The two plugins share an identifier. EchoApp uses that identifier to route opaque payloads to the
right pair. Plugin A cannot see plugin B's stream unless the plugins explicitly coordinate.

## Connection flow

1. The client advertises itself—through Bonjour on Apple platforms or an ADB-assisted handshake on
   Android.
2. EchoApp selects a client and establishes a WebSocket connection.
3. The client sends its app information and the identifiers of its registered plugins.
4. EchoApp creates a `PluginConnection` for each matching pair and calls its lifecycle hooks.
5. Each pair exchanges `PluginMessage` envelopes until the client disconnects.

The envelope contains a plugin identifier, optional command, and opaque data. `PluginConnection`
provides Codable conveniences on Swift and Moshi-based event helpers on Android, but plugins can
choose the contract that fits their use case.

## Responsibilities

| Layer | Owns | Does not own |
|---|---|---|
| EchoApp host | Discovery, WebSocket lifecycle, plugin loading, routing | Plugin schemas or business logic |
| Client plugin | Collecting data, responding to commands, app-facing API | Desktop presentation |
| Desktop plugin | Decoding data, local view state, SwiftUI presentation | How the host transports other plugins |

## Desktop plugin loading

Built-in plugins ship with EchoApp. External plugins are macOS bundles with the `.echoplugin`
extension. EchoApp loads them from:

```text
~/Library/Application Support/Echo/Plugins/
```

Each bundle contains a framework, `PluginInfo.plist`, and an exported provider function. The provider
returns one or more `DesktopPlugin` types for the host to instantiate. See
[Build a plugin](../../guides/build-a-plugin/) and the
[bundle format reference](https://github.com/block/echoapp/blob/main/Documentation/PluginStructure.md).

## Security boundary

EchoApp is a development tool, not a production telemetry system. It does not inspect or redact
plugin payloads. Treat every capture as potentially sensitive, keep the SDK out of production
variants, and sanitize data before sharing it in issues, chats, or AI prompts.
