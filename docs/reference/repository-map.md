---
title: Repository map
description: Find the macOS app, SDKs, plugins, command-line tools, examples, and documentation.
section: Reference
permalink: /reference/repository-map/
---

# Repository map

EchoApp keeps the desktop host and both mobile SDKs in one public repository so a protocol change
can update every side together.

| Path | What lives there |
|---|---|
| `App/` | Xcode project and macOS application wrapper. |
| `EchoApp/` | Swift package for the desktop host, CLI, MCP server, tools, and built-in desktop plugins. |
| `Sources/` | Public Swift SDK: EchoClient, connection and plugin APIs, shared UI, and optional plugins. |
| `Tests/` | Swift SDK and plugin API tests. |
| `android/` | Android client, plugin API, sample app, and Gradle build support. |
| `Examples/` | Small external consumers such as the SwiftPM example. |
| `Documentation/` | Versioning and low-level bundle format references. |
| `docs/` | This documentation site. |
| `Scripts/` | Public build and release verification tools. |

The root `Package.swift` is the package external Swift applications depend on. `EchoApp/Package.swift`
builds the macOS host and consumes the root SDK through a local package dependency. Keeping those
manifests separate ensures the app and external `.echoplugin` bundles share one dynamic copy of the
plugin API type metadata.

Start with [Develop EchoApp](../../guides/develop-echoapp/) for build commands or browse the
[repository on GitHub](https://github.com/block/echoapp).
