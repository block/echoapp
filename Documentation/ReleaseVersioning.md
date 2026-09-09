# EchoApp release versioning

EchoApp desktop releases use Semantic Versioning 2.0.0 without a prefix as
their exact release identity, for example `3.0.0-rc.1` or `3.0.0`.

| Consumer | Value for `3.0.0-rc.1` |
| --- | --- |
| GitHub release and SwiftPM tag | `3.0.0-rc.1` |
| Android publication tag | `android-v3.0.0-rc.1` |
| EchoAppReleaseVersion | `3.0.0-rc.1` |
| `echoapp --version` | `3.0.0-rc.1` |
| `CFBundleShortVersionString` | `3.0.0` |
| `CFBundleVersion` | Numeric date-based build number |

`Scripts/release_version.sh` accepts an exact bare or `v`-prefixed version and
validates it before build scripts stamp `EchoAppReleaseVersion`. Apple bundle
version fields remain numeric while the exact key preserves prerelease
precedence for consumers that opt into release updates.

The updater reads published GitHub Releases and selects by Semantic Version
precedence. Stable clients ignore prereleases, while prerelease clients include
them. Build metadata is retained as release identity but never causes an update.

The Android Maven publication uses the same exact product version and rendered
commit, expressed as the technical `android-v<version>` tag. Its staged public
workflow calls `Scripts/release_version.sh`, so Android and desktop releases
share one SemVer grammar. That tag triggers Maven Central publishing but never
creates a GitHub Release, so the desktop updater only sees the human-facing
bare Semantic Version release. Once Central has accepted the signed artifacts and
they are publicly available, the Android workflow attaches the checksummed audit
bundle to that same bare-version GitHub Release.
