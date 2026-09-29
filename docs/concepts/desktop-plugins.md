---
title: Desktop plugins
description: Native SwiftUI tools loaded into the EchoApp macOS host.
section: Concepts
permalink: /concepts/desktop-plugins/
---

# Desktop plugins

A desktop plugin is a macOS Swift module loaded by EchoApp. It receives data from a corresponding
client plugin, manages local presentation state, and renders a native SwiftUI view.

## Core pieces

| Component | Purpose |
|---|---|
| `DesktopPlugin` | Declares metadata and connection lifecycle, and builds the plugin view. |
| `PluginProvider` | Gives EchoApp the desktop plugin types exported by an external bundle. |
| `PluginInfo.plist` | Describes the bundle before its Swift code is loaded. |
| SwiftUI view model | Decodes messages and owns the view's observable state. |

The `DesktopPlugin` protocol requires `init()`, `metadata`, `makeView()`, `onConnect(_:)`, and
`onDisconnect()`. Store subscriptions for only as long as the connection is active and update UI
state on the main actor.

## Built in or external

Built-in plugins are compiled with EchoApp and share its release cadence. External plugins are
packaged as `.echoplugin` bundles and installed under the user's Application Support directory.
Choose an external bundle when a plugin belongs to another project or needs independent releases.

The shared `EchoPluginUI` product includes tables, detail panes, syntax highlighting, copy controls,
and other components that make custom plugins feel at home in EchoApp.

Continue with [Build a plugin](../../guides/build-a-plugin/) or inspect the
[built-in plugins](../../reference/plugins/) for production examples.
