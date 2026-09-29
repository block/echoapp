---
title: Integrate an Android app
description: Add EchoClient and client plugins to an Android debug build with Gradle.
section: Integrate
permalink: /guides/integrate-android/
---

# Integrate an Android app

The Android SDK is split into a connection module and a plugin API. Declare both as debug-only
dependencies so they are excluded from release variants.

## Add the dependencies

```kotlin
dependencies {
    debugImplementation("xyz.block.echoapp:echo-client:<version>")
    debugImplementation("xyz.block.echoapp:echo-plugin-api:<version>")
}
```

Maven Central is the canonical distribution channel. Use one version for both modules.

## Build and start a client

Create one `EchoClient` for the application process, register plugin instances in the builder, and
start it from a coroutine running off the main thread.

```kotlin
val loggingPlugin = LoggingPlugin(
    currentTimestampProvider = { Instant.now().toString() },
)

val echoClient = EchoClient.Builder(context)
    .addPlugins(loggingPlugin)
    .build()

applicationScope.launch(Dispatchers.IO) {
    echoClient.start()
}
```

Call `stop()` when the development service or process that owns the client shuts down.

## Wire a built-in plugin

Registering a plugin creates the transport, but the plugin still needs a source of app events. For
example, `LoggingPlugin` can be connected to Timber with `EchoTree`:

```kotlin
val echoTree = EchoTree(loggingPlugin)
Timber.plant(echoTree)

// When the owner is disposed:
Timber.uproot(echoTree)
```

Networking, accessibility, key-value store, analytics, and crash reporting integrations each have
their own source-specific setup. Read the implementation and sample app under `android/sample/` for
working examples.

## Device discovery

EchoApp uses ADB to find Android emulators and connected devices. Before opening the desktop app,
verify that the target appears as `device` rather than `offline` or `unauthorized`:

```sh
adb devices
```

The SDK also supports a Unix-domain-socket handshake for environments that tunnel the connection.
Most applications should start with the default `EchoClient.Builder(context)` discovery path.

## Keep it in debug builds

Use `debugImplementation` and initialize EchoApp from debug-only source sets or dependency
injection bindings. The client is a debugging transport; its plugins can expose app state and must
not be reachable in production.

Next, explore the [plugin catalog](../../reference/plugins/) or [build a custom plugin](../build-a-plugin/).
