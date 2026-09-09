# Public build matrix

Run the complete public build matrix from a checkout of this repository:

```sh
Scripts/verify_public_builds.sh
```

Verify Android separately with an installed Android SDK:

```sh
ANDROID_HOME=/path/to/android-sdk Scripts/verify_public_android_build.sh
```

That command archives the tracked public tree, uses a fresh Gradle home, clears
all repository overrides and publishing credentials, refreshes dependencies,
builds every Android module, publishes the two SDK modules to an isolated local
Maven repository, and validates their release inventory and metadata.

The script first archives the tracked public tree, then uses `xcrun swift` and
temporary SwiftPM scratch directories from that archive. It therefore cannot
rely on checkout-only files, private repositories, credentials, or signing
certificates. Git ignores system and global configuration, clears credential
helpers, disables prompting, and disables SSH-agent authentication. It covers:

- the public SDK root (`xcrun swift build` and `xcrun swift test`);
- the macOS EchoApp package, `echoapp`, and `echo-tool`;
- `Examples/SPMExample`;
- an unsigned Release archive of `App/App.xcodeproj`'s `Echo` scheme;
- an iOS Simulator `AccessibilityPlugin` consumer, including
  `AccessibilitySnapshot` and UIKit; and
- a separate `EchoClient` consumer resolved from a locally created, exact
  source-control tag.

The two external-consumer checks use a disposable `file://` Git repository.
They exercise SwiftPM's exact-version source-control resolution without a
network account or a live release tag. SwiftPM may still fetch the public,
declared package dependencies on a cold machine.

Every SwiftPM invocation also uses temporary cache, configuration, and security
paths. The Xcode archive uses the system Git provider and a separate temporary
cloned-source-packages directory and package cache, so neither can resolve
through user-level SwiftPM/Xcode package state. The matrix runs Git, SwiftPM,
and Xcode from an empty temporary home with an empty `.netrc`, no SSH agent or
default SSH identity, and no Git credential helper. Run its static isolation
regression assertions with:

```sh
Scripts/verify_public_builds_test.sh
Scripts/verify_public_android_build_test.sh
```
