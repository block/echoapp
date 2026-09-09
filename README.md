<div align="center">

# EchoApp

_**Live debugging for your mobile app - network traffic, logs, analytics, and more, streamed to your desktop.**_

<p>
  <a href="https://opensource.org/licenses/Apache-2.0">
    <img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="License: Apache-2.0">
  </a>
</p>

</div>

EchoApp is a debugging companion for mobile development: a macOS desktop app plus
client SDKs for Swift and Android. Add the client SDK to your app and it becomes
discoverable from the desktop app on your local network; plugins then stream live
data - network requests, logs, analytics events, key-value stores, accessibility
snapshots, crash reports, and more - from the running app into inspectable
desktop UIs.

## What's in the box

- **Desktop app** - the macOS host (`App/`, `EchoApp/`) with built-in desktop
  plugins for Networking, Logging, Analytics, App Info, Key-Value Store,
  Accessibility, Navigation, Debug Menu, and Crash Reporting, plus an `EchoMCP`
  Model Context Protocol server so coding agents can read the same live data.
- **Swift SDK** (`Sources/`) - `EchoClient`, `EchoConnection`, and the plugin
  API for iOS and macOS apps (iOS 14+ / macOS 14+). Opt-in client plugins live
  in [`Sources/OptionalPlugins/`](Sources/OptionalPlugins/README.md).
- **Android SDK** (`android/`) - `client` and `plugin-api` modules; see
  [`android/README.md`](android/README.md).
- **Plugin API** - build your own plugin pair: a client plugin in your app and
  a `.echoplugin` bundle the desktop app loads. The bundle format is documented
  in [`Documentation/PluginStructure.md`](Documentation/PluginStructure.md).

## Install

### Desktop app (macOS 14+)

Download the latest release from
[GitHub Releases](https://github.com/block/echoapp/releases). The app checks
GitHub Releases for updates.

All public artifacts share the version and tag mapping in
[Release versioning](Documentation/ReleaseVersioning.md).

### Swift SDK

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/block/echoapp", from: "<version>"),
]
```

Products: `EchoClient` (connect your app to the desktop app), `EchoConnection`,
`EchoPluginAPI` and `EchoDesktopPlugin` (author desktop plugins), and the
optional client plugins `AccessibilityPlugin` and `KeyValueStorePlugin`.

### Android SDK

```groovy
debugImplementation "xyz.block.echoapp:echo-client:<version>"
debugImplementation "xyz.block.echoapp:echo-plugin-api:<version>"
```

## Quick start

- **Connect your app:** create an `EchoClient` in your app, add the plugins you
  want, and start it - your app appears in the desktop app on the same network.
  See [`android/README.md`](android/README.md) for Android; on Swift, see the
  `EchoClient` sources under [`Sources/EchoClient/`](Sources/EchoClient/).
- **Write a plugin:** start from the example in [`Examples/`](Examples/)
  (`SPMExample` consumes the SDK via SwiftPM), the built-in plugins under
  [`EchoApp/Sources/Plugins/`](EchoApp/Sources/Plugins/), and the shared UI kit
  in [`Sources/EchoPluginUI/`](Sources/EchoPluginUI/README.md).

## Building from source

Swift 5.10+ and Xcode with the macOS 14 SDK are required for the app.

```sh
# Swift SDK (repo root)
xcrun swift build
xcrun swift test

# Desktop app: open App/App.xcodeproj in Xcode and run the Echo scheme,
# or build the CLI and tools directly:
cd EchoApp && xcrun swift build      # builds the echoapp CLI and echo-tool

# Android SDK. Build-only code generators are compiled from this checkout.
cd android
./gradlew build
```

To exercise every public Swift and macOS distribution surface from a clean
temporary build directory, including an iOS Simulator AccessibilityPlugin
consumer and an exact-version external EchoClient consumer, run:

```sh
Scripts/verify_public_builds.sh
```

The public matrix builds an archive of the tracked public tree with no private
repositories, credentials, or signing certificates. See
[`Scripts/README.md`](Scripts/README.md) for the full list of checks.

## Community

- [CONTRIBUTING.md](CONTRIBUTING.md) - how to get set up and send changes
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) - community standards
- [GOVERNANCE.md](GOVERNANCE.md) - how the project is governed
- [SECURITY.md](SECURITY.md) - reporting vulnerabilities privately

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
