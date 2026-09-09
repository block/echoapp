# Sealed Swift compatibility build support

EchoApp's Android event models use a Moshi KSP processor to produce the same
sealed-type JSON representation as Swift `Codable`. The processor and its
ProGuard-rule generator live here as source so a clean checkout can build using
only the public repositories configured in `android/settings.gradle`.

These modules are build tools. They are not part of EchoApp's runtime API and
must not appear in the published `echo-client` or `echo-plugin-api` metadata.
The Maven release workflow checks that boundary before uploading artifacts.

The code is covered by this repository's Apache License 2.0.
