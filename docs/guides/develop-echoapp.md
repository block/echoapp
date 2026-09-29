---
title: Develop EchoApp
description: Build the macOS app, Swift SDK, CLI, and Android SDK from a source checkout.
section: Integrate
permalink: /guides/develop-echoapp/
---

# Develop EchoApp

EchoApp is a monorepo containing the macOS host, Swift SDK, Android SDK, command-line tools, and
built-in plugins.

## Requirements

- macOS 14 or newer
- Swift 5.10 or newer
- Xcode with the macOS 14 SDK
- JDK and Android SDK tooling for Android changes

## Clone and build the Swift SDK

```sh
git clone https://github.com/block/echoapp.git
cd echoapp
xcrun swift build
xcrun swift test
```

The root package contains the public Swift SDK. The desktop app and tools have their own manifest:

```sh
cd EchoApp
xcrun swift build
xcrun swift test
```

## Run the macOS app

Open `App/App.xcodeproj`, select the **Echo** scheme, choose **My Mac**, and run. The Xcode project
embeds the dynamic `EchoDesktopPlugin` framework and assembles the built-in plugin targets.

If Xcode reports a missing package product, make it use its built-in Git implementation, restart
Xcode, and resolve packages again:

```sh
defaults write com.apple.dt.Xcode IDEPackageSupportUseBuiltinSCM YES
```

## Build Android

```sh
cd android
./gradlew build
```

The sample app exercises discovery and several built-in client plugins. Use it to validate changes
that cross the Android transport or plugin API boundary.

## Verify public distribution surfaces

The repository includes a clean-room verifier for the public Swift and macOS builds:

```sh
Scripts/verify_public_builds.sh
```

Before sending a pull request, run the smallest relevant test set, then the full verifier when a
change affects package topology, release artifacts, or public dependencies. See
[CONTRIBUTING.md](https://github.com/block/echoapp/blob/main/CONTRIBUTING.md) for sign-off and review
requirements.
