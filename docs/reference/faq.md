---
title: Frequently asked questions
description: Common questions about EchoApp's scope, safety, transport, and plugin model.
section: Reference
permalink: /reference/faq/
---

# Frequently asked questions

## Is EchoApp a proxy?

No. The mobile app's client plugins observe data and send it to the desktop over an EchoApp
connection. Network inspection therefore requires an interceptor or protocol hook in the
development app; EchoApp does not install a system-wide proxy or certificate.

## Why build another mobile debugging tool?

EchoApp emphasizes native SwiftUI desktop plugins, a small two-way transport, and app-specific
extensibility. Teams can use the built-in tools while adding a focused plugin that understands their
own architecture, without teaching the host about that plugin's schema.

## Does EchoApp support production apps?

It is designed for development builds. Client plugins may expose logs, requests, preferences, debug
controls, and other sensitive state. Exclude the SDK and its initialization from production build
variants.

## Does data leave my machine?

EchoApp's client-to-host connection is local. Data can leave the machine if you copy it, attach it
to an issue, pipe it into another service, or give an AI tool access through MCP. Your handling of
captures is part of the security boundary.

## Can iOS and Android share a desktop plugin?

Yes. Give both client plugins the same identifier and serialize the same data contract. JSON field
names, optionality, enum values, and timestamp units must agree across platforms.

## Can a plugin send commands back to the app?

Yes. `PluginConnection` is bidirectional. Use commands for explicit development operations such as
refreshing a snapshot, toggling a debug control, or installing a network fixture. Avoid hidden or
destructive behavior.

## Where are external desktop plugins installed?

```text
~/Library/Application Support/Echo/Plugins/
```

Built-in plugins ship inside EchoApp and do not need to be installed there.

## Can I use EchoApp without the GUI?

Yes. The [`echoapp` CLI](../../tools/cli/) connects directly to clients and captures every plugin
stream as JSONL. The desktop app also exposes selected plugin data through its [MCP server](../../tools/mcp/).

## How do I propose a plugin or documentation improvement?

Open an issue or pull request in [block/echoapp](https://github.com/block/echoapp). Keep reusable,
general-purpose plugins in the public project; application-specific plugins can live with the app
that owns their data contract.
