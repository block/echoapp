---
title: Build a plugin
description: Create a paired client and SwiftUI desktop plugin with a shared message contract.
section: Integrate
permalink: /guides/build-a-plugin/
---

# Build a plugin

A useful EchoApp plugin begins with one focused question: what do you need to observe or control in
the running app? Model that exchange first, then implement the client and desktop sides around it.

## Define the contract

Use a small, versionable payload. Swift's `PluginConnection` encodes Codable values as JSON and
represents dates as Unix milliseconds.

```swift
struct CounterSnapshot: Codable {
    let value: Int
    let recordedAt: Date
}
```

If Android sends the same payload, mirror the serialized field names and timestamp representation
in Kotlin. Add a contract version or new command before making a breaking schema change.

## Implement the Swift client

```swift
import EchoPluginAPI

@MainActor
final class CounterClientPlugin: ClientPlugin {
    let id: PluginIdentifier = "com.example.echo.counter"
    let version = "1.0.0"
    private var connection: PluginConnection?

    func onConnect(_ connection: PluginConnection) {
        self.connection = connection
    }

    func onDisconnect() {
        connection = nil
    }

    func record(value: Int) {
        try? connection?.send(CounterSnapshot(value: value, recordedAt: Date()))
    }
}
```

Register one long-lived instance with `EchoClient` and call `record(value:)` from the development
code path you want to inspect.

## Implement the desktop plugin

```swift
import Combine
import EchoPluginAPI
import SwiftUI

final class CounterDesktopPlugin: DesktopPlugin, ObservableObject {
    let metadata = DesktopPluginMetadata(
        id: "com.example.echo.counter",
        version: "1.0.0",
        category: .data,
        displayName: "Counter",
        icon: Image(systemName: "number"),
        description: "Shows counter changes",
        orgId: "com.example",
        orgDisplayName: "Example"
    )

    @Published fileprivate var snapshots: [CounterSnapshot] = []
    private var subscriptions = Set<AnyCancellable>()

    required init() {}

    func makeView() -> AnyView {
        AnyView(CounterPluginView(plugin: self))
    }

    func onConnect(_ connection: PluginConnection) {
        connection.receive(CounterSnapshot.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.snapshots.append($0) }
            .store(in: &subscriptions)
    }

    func onDisconnect() {
        subscriptions.removeAll()
    }
}

private struct CounterPluginView: View {
    @ObservedObject var plugin: CounterDesktopPlugin

    var body: some View {
        List(plugin.snapshots, id: \.recordedAt) { snapshot in
            Text("\(snapshot.value)")
        }
    }
}
```

The identifiers must match. Keep Combine subscriptions connection-scoped so a reconnect does not
duplicate events.

## Package an external desktop plugin

An external plugin exports a provider that hands its types to EchoApp:

```swift
final class CounterPluginProvider: PluginProvider {
    override func providePluginTypes() -> [any DesktopPlugin.Type] {
        [CounterDesktopPlugin.self]
    }
}

@_cdecl("makePluginProvider")
public func makePluginProvider() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(CounterPluginProvider()).toOpaque()
}
```

Add `PluginInfo.plist` to the target resources, build the dynamic library, and assemble the
`.echoplugin` bundle with `echo-tool`. From an EchoApp checkout, point the tool at your plugin's
manifest:

```sh
cd /path/to/echoapp/EchoApp
swift run echo-tool build-plugin CounterPlugin \
  --bundle-identifier com.example.echo.counter \
  --package-path /path/to/counter-plugin/Package.swift \
  --output-dir /path/to/counter-plugin/build
```

Install the resulting bundle in `~/Library/Application Support/Echo/Plugins/`. The complete bundle
layout is documented in
[PluginStructure.md](https://github.com/block/echoapp/blob/main/Documentation/PluginStructure.md).

## Test the pair

1. Unit test encoding and decoding with fixtures shared between platforms.
2. Connect a small development app and send one known payload.
3. Disconnect and reconnect to catch leaked subscriptions or stale state.
4. Exercise malformed and newer payloads without crashing the desktop host.
5. Verify that production build variants do not contain or start the client plugin.
