---
title: Debug the app you are building, while it runs
description: EchoApp streams network traffic, logs, analytics, app state, and custom debug data from iOS and Android to your Mac.
hide_breadcrumbs: true
wide: true
---

<div class="hero">
  <div class="hero-kicker">Open source mobile debugging</div>
  <h1>See what your app is doing. Right now.</h1>
  <p class="lead">EchoApp streams network traffic, logs, analytics, app state, and your own debug data from iOS and Android into a native macOS app—or straight to your terminal and coding agent.</p>
  <div class="hero-actions">
    <a class="button button-primary" href="getting-started/">Get started <span aria-hidden="true">→</span></a>
    <a class="button" href="https://github.com/block/echoapp">View on GitHub <span aria-hidden="true">↗</span></a>
  </div>
</div>

## One connection, many debugging tools

EchoApp is a small host with a plugin system. Add the client SDK to a development build, choose the
plugins you need, and connect from your Mac. Each plugin owns its data contract and user interface;
the host handles discovery, transport, and lifecycle.

<div class="card-grid">
  <a class="card" href="getting-started/">
    <span class="card-icon">01</span>
    <strong>Connect your app</strong>
    <span>Integrate the Swift or Android SDK and make a simulator, emulator, or device discoverable.</span>
  </a>
  <a class="card" href="reference/plugins/">
    <span class="card-icon">02</span>
    <strong>Use built-in plugins</strong>
    <span>Inspect requests, logs, analytics events, accessibility, crashes, preferences, and more.</span>
  </a>
  <a class="card" href="guides/build-a-plugin/">
    <span class="card-icon">03</span>
    <strong>Build your own</strong>
    <span>Define a Codable or JSON contract, then pair client logic with a native SwiftUI view.</span>
  </a>
  <a class="card" href="tools/cli/">
    <span class="card-icon">04</span>
    <strong>Debug headlessly</strong>
    <span>Capture plugin streams as JSONL and query them from scripts, CI, or an AI coding agent.</span>
  </a>
</div>

## Designed for development builds

EchoApp runs locally and is intentionally unopinionated about your payloads. The desktop host does
not need to understand a plugin's data. This makes it useful for general tools such as network
inspection and for the app-specific tools only your team can imagine.

<div class="callout">
  <strong>Keep it out of production.</strong> Add the client and its plugins only to debug or
  development variants. Debug payloads can contain credentials, personal data, or implementation
  details that should not leave a developer-controlled environment.
</div>

## Choose a path

- New to EchoApp? Start with [Get started](getting-started/).
- Adding it to an application? Follow the [Swift](guides/integrate-swift/) or
  [Android](guides/integrate-android/) integration guide.
- Curious how plugin pairs communicate? Read [Architecture](concepts/architecture/).
- Extending EchoApp? Build a [custom plugin](guides/build-a-plugin/).
- Automating a debugging workflow? Use the [CLI](tools/cli/) or [MCP server](tools/mcp/).
