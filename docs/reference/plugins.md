---
title: Plugin catalog
description: The debugging tools built into the public EchoApp desktop application.
section: Reference
permalink: /reference/plugins/
---

# Plugin catalog

The public EchoApp desktop application includes nine foundational plugins. A plugin becomes useful
when the connected app registers its matching client integration.

<div class="plugin-list">
  <div class="plugin-pill"><strong>Network Monitor</strong><span>Requests, responses, rules, fixtures</span></div>
  <div class="plugin-pill"><strong>Logging</strong><span>Structured and plain-text logs</span></div>
  <div class="plugin-pill"><strong>Analytics</strong><span>Live event names and properties</span></div>
  <div class="plugin-pill"><strong>App Info</strong><span>Build and runtime metadata</span></div>
  <div class="plugin-pill"><strong>Key Value Store</strong><span>Preferences and custom stores</span></div>
  <div class="plugin-pill"><strong>Accessibility</strong><span>Accessibility hierarchy audits</span></div>
  <div class="plugin-pill"><strong>Navigation</strong><span>App navigation stack</span></div>
  <div class="plugin-pill"><strong>Debug Menu</strong><span>Remote debug controls</span></div>
  <div class="plugin-pill"><strong>Crash Reporting</strong><span>Development crash reports</span></div>
</div>

## Network Monitor

Inspect HTTP requests and responses, filter traffic, and replace selected responses with local
fixtures or error statuses. See the [Network Monitor guide](../../tools/network-monitor/).

## Logging

Stream development logs into a searchable table. Android includes a Timber tree integration; other
clients can send the shared table-row contract or a custom logging payload.

## Analytics

Observe event names and properties as instrumentation fires. The desktop plugin also exposes
analytics queries through MCP. Never send production customer analytics into a development capture.

## App Info

Display build, device, environment, or other key/value metadata. This is a good first plugin for
confirming that an integration is connected and running the expected build.

## Key Value Store

Browse and, where supported, edit stores such as `UserDefaults`, Android `SharedPreferences`, and
custom providers. Treat write operations as state mutations and make their development-only scope
clear.

## Accessibility

Capture the current accessibility hierarchy and review labels, traits, frames, and common audit
problems from the desktop.

## Navigation

Visualize the navigation state reported by a client integration. The contract is intentionally
plugin-owned so applications can map their navigation architecture into a useful representation.

## Debug Menu

Mirror an app's development controls on the desktop. Supported controls can also be searched and
mutated from the CLI, enabling repeatable setup for debugging and tests.

## Crash Reporting

Persist development crashes on the client and inspect their report after the next launch and
connection. This complements, rather than replaces, a production crash reporting system.

Need a tool that is not listed? [Build a plugin](../../guides/build-a-plugin/).
