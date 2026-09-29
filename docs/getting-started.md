---
title: Get started
description: Install EchoApp, connect a development build, and inspect your first live debug stream.
section: Start here
permalink: /getting-started/
---

# Get started

EchoApp pairs a macOS desktop host with a lightweight client in your iOS or Android development
build. This guide gets the two connected and confirms that plugin data is flowing.

## What you need

- A Mac running macOS 14 or newer
- Xcode and Swift 5.10+ for Swift development, or the Android SDK and `adb` for Android development
- A development build of your app; do not ship EchoApp client code in production variants

## Install the desktop app

Download the latest `EchoApp` archive from [GitHub Releases](https://github.com/block/echoapp/releases),
unzip it, and move `EchoApp.app` into `/Applications`.

To build the app yourself, clone the repository, open `App/App.xcodeproj`, select the **Echo**
scheme and run it on **My Mac**.

## Connect a client

<div class="steps">
  <div class="step">
    <h3>Add the SDK</h3>
    <p>Follow the <a href="../guides/integrate-swift/">Swift</a> or <a href="../guides/integrate-android/">Android</a> guide. Start with App Info or Logging so the first connection is easy to recognize.</p>
  </div>
  <div class="step">
    <h3>Start EchoClient</h3>
    <p>Start the client from a debug-only application lifecycle hook. On iOS, accept the local-network permission prompt. On Android, make sure <code>adb devices</code> can see the emulator or device.</p>
  </div>
  <div class="step">
    <h3>Choose the device</h3>
    <p>Open EchoApp. Select your app from the device picker. Bonjour discovers Apple clients on the local network; Android clients are discovered through ADB.</p>
  </div>
  <div class="step">
    <h3>Open a plugin</h3>
    <p>Select a plugin in the sidebar and trigger the matching behavior in your app. Data appears as the client sends it.</p>
  </div>
</div>

## Confirm the connection

The selected device and connection status appear at the top of the EchoApp window. The **App Info**
plugin is a useful smoke test because it can send a small snapshot immediately after connecting.

If the app is not listed, work through [Troubleshooting](../troubleshooting/). Most first-run issues
come from local-network permissions, a client that was never started, or an Android device that is
not visible to ADB.

## Where to go next

- Browse the [built-in plugin catalog](../reference/plugins/).
- Learn how [the host and plugin pairs fit together](../concepts/architecture/).
- Capture the same streams without the GUI using the [EchoApp CLI](../tools/cli/).
- Create an app-specific tool with [Build a plugin](../guides/build-a-plugin/).
