# Echo Android SDK

The Android client SDK for Echo: makes an Android app discoverable by the Echo desktop app and streams plugin data (logging, networking, analytics, and more) to it.
Modules: `client/` (connection + discovery), `plugin-api/` (plugin interfaces and built-in plugins), `sample/` (demo app). Build-only Moshi processors live under `build-support/` so source builds require only public dependency repositories. Pairs with the Echo desktop app in this repository.

## Releases

Maven Central is the canonical distribution channel. The `android-v*` workflow validates the
exact two-module inventory, detached signatures, and SHA-256 evidence before staging Central.
After Central publication is manually approved and publicly visible, the workflow attaches
that same audit bundle to the matching unified GitHub Release for convenience.
