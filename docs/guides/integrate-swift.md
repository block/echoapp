---
title: Integrate a Swift app
description: Add EchoClient to an iOS or macOS development build with Swift Package Manager.
section: Integrate
permalink: /guides/integrate-swift/
---

# Integrate a Swift app

The Swift SDK supports iOS 14+ and macOS 14+. Add it only to development configurations so debug
transport and plugins never become part of a production binary.

## Add the package

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/block/echoapp
```

Add the `EchoClient` product to your application target. Add optional products such as
`AccessibilityPlugin` or `KeyValueStorePlugin` only when you need them.

For a manifest-based package:

```swift
dependencies: [
    .package(url: "https://github.com/block/echoapp", from: "<version>")
]
```

## Start the client

Register plugins before starting the shared client. This minimal example exposes app information:

```swift
#if DEBUG
import EchoClient

@MainActor
func startEcho() {
    let client = EchoClient.shared
    client.appInfoPlugin.setEntries([
        .init(scope: "Build", key: "Channel", value: "Debug")
    ])
    client.addPlugin(client.appInfoPlugin)
    client.start()
}
#endif
```

Call `startEcho()` from your development app's startup path. Keep the entire integration behind
`#if DEBUG` or an equivalent build condition.

## Add another plugin

Each plugin is an object conforming to `ClientPlugin`. Create it once, register it with
`addPlugin(_:)`, then keep using that instance from your app-facing debug API.

```swift
let plugin = MyClientPlugin()
EchoClient.shared.addPlugin(plugin)
EchoClient.shared.start()
```

Calling `addPlugin` with the same identifier replaces the previous instance. Calling `start()` is
safe from any connection state; it stops the previous connection and starts with the selected
connection mode.

## Discovery and manual connections

The default `.bonjour` mode advertises the app on the local network. The user must grant local
network access. When discovery is unavailable, connect directly to a WebSocket URL:

```swift
EchoClient.shared.start(mode: .manual(url: serverURL))
```

The selected mode is persisted. Call `start(mode: .bonjour)` to return to automatic discovery.

## App Transport Security and privacy

EchoApp uses a local development connection. Configure only the narrow development entitlements or
transport exceptions your app requires, and keep those settings out of release configurations.
Plugins may observe network bodies, logs, preferences, and other sensitive state; never enable them
for customer builds.

Next, explore the [plugin catalog](../../reference/plugins/) or [build a custom plugin](../build-a-plugin/).
