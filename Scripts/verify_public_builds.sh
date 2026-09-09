#!/usr/bin/env bash
# Verifies the build surfaces shipped to public EchoApp consumers.
#
# This script intentionally uses an empty temporary scratch directory rather
# than the checkout's .build directory. It therefore catches dependencies on
# private checkouts, credentials, or previously-built artifacts.

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly public_root="$(cd "$script_dir/.." && pwd -P)"
readonly temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/echo-public-build.XXXXXX")"
readonly temporary_home_path="$temporary_root/home"
readonly release_root="$temporary_root/echo"
readonly swiftpm_cache_path="$temporary_root/swiftpm-cache"
readonly swiftpm_config_path="$temporary_root/swiftpm-config"
readonly swiftpm_security_path="$temporary_root/swiftpm-security"
readonly cloned_source_packages_path="$temporary_root/cloned-source-packages"
readonly xcode_package_cache_path="$temporary_root/xcode-package-cache"

mkdir -p "$temporary_home_path"
: > "$temporary_home_path/.netrc"

# SwiftPM invokes Git while resolving packages. Ignore system/global Git
# configuration, clear credential helpers, and disable interactive and SSH-agent
# authentication so a private dependency cannot appear public.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/false
export SSH_ASKPASS=/usr/bin/false
export SSH_AUTH_SOCK=/dev/null
export GIT_SSH_COMMAND='ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=none -o IdentityFile=none'

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

run_with_isolated_credentials() {
    env \
        -u SWIFTPM_MIRROR_CONFIG \
        -u SWIFTPM_REGISTRY_TOKEN \
        -u SWIFTPM_REGISTRY_LOGIN \
        -u SWIFTPM_REGISTRY_PASSWORD \
        -u SWIFTPM_SOURCE_CONTROL_TOKEN \
        -u SWIFTPM_NETRC_DATA \
        HOME="$temporary_home_path" \
        NETRC="$temporary_home_path/.netrc" \
        "$@"
}

run() {
    printf '\n==> %s\n' "$*"
    run_with_isolated_credentials "$@"
}

run_swift_in() {
    local directory="$1"
    shift
    (
        cd "$directory"
        run xcrun swift "$@" \
            --cache-path "$swiftpm_cache_path" \
            --config-path "$swiftpm_config_path" \
            --security-path "$swiftpm_security_path" \
            --disable-keychain \
            --enable-netrc \
            --netrc-file "$temporary_home_path/.netrc"
    )
}

archive_public_tree() {
    local repository_root
    repository_root="$(run_with_isolated_credentials git -C "$public_root" rev-parse --show-toplevel)"

    if [[ "$repository_root" != "$public_root" ]]; then
        echo "Run this verifier from a standalone checkout of the public repository." >&2
        exit 1
    fi

    # Keep the fixture directory name aligned with the public package identity
    # so the consumer uses the same `package: "echo"` reference it would use
    # against the published repository URL.
    mkdir -p "$release_root"
    run_with_isolated_credentials git -C "$public_root" archive HEAD | tar -xf - -C "$release_root"

    # `git archive` is the boundary: it cannot include untracked or modified
    # files beside the public tree in the source checkout.
    [[ ! -e "$release_root/.git" ]]

    run git -C "$release_root" init --quiet
    run git -C "$release_root" config user.email "public-build-matrix@example.invalid"
    run git -C "$release_root" config user.name "Public build matrix"
    run git -C "$release_root" add --all
    run git -C "$release_root" commit --quiet --message "release fixture"
    run git -C "$release_root" tag 0.0.0
}

write_consumer() {
    local directory="$1"
    local product="$2"

    mkdir -p "$directory/Sources/Consumer"
    cat > "$directory/Package.swift" <<EOF
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Consumer",
    platforms: [.iOS(.v14), .macOS(.v14)],
    dependencies: [
        .package(url: "file://$release_root", exact: "0.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "$product", package: "echo"),
            ]
        ),
    ]
)
EOF

    cat > "$directory/Sources/Consumer/main.swift" <<EOF
import $product

print("$product consumer built")
EOF
}

simulator_architecture() {
    case "$(uname -m)" in
        arm64|x86_64)
            uname -m
            ;;
        *)
            printf 'arm64\n'
            ;;
    esac
}

readonly scratch_path="$temporary_root/scratch"

# Archive before any build. Every check below therefore sees exactly the files
# that a public release contains, not untracked or private-adjacent checkout
# files that can accidentally mask omitted public files.
archive_public_tree

# Public Swift package: both commands deliberately start from one empty scratch
# directory, exactly as a fresh clone does.
run_swift_in "$release_root" build --scratch-path "$scratch_path/public-root"
run_swift_in "$release_root" test --scratch-path "$scratch_path/public-root"

# macOS desktop package, its shipped command-line tools, and their tests.
run_swift_in "$release_root/EchoApp" build --scratch-path "$scratch_path/echo-app" --product echoapp
run_swift_in "$release_root/EchoApp" build --scratch-path "$scratch_path/echo-app" --product echo-tool
run_swift_in "$release_root/EchoApp" test --scratch-path "$scratch_path/echo-app"

# Example package that consumes the SDK through a local public package path.
run_swift_in "$release_root/Examples/SPMExample" build --scratch-path "$scratch_path/spm-example"

# App.xcodeproj is the distribution build surface. Archiving without signing is
# intentional: signing is a release concern, not a public source prerequisite.
run xcrun xcodebuild \
    -quiet \
    -project "$release_root/App/App.xcodeproj" \
    -scheme Echo \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$temporary_root/derived-data" \
    -scmProvider system \
    -clonedSourcePackagesDirPath "$cloned_source_packages_path" \
    -packageCachePath "$xcode_package_cache_path" \
    -archivePath "$temporary_root/Echo.xcarchive" \
    archive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

write_consumer "$temporary_root/echo-client-consumer" EchoClient
run_swift_in "$temporary_root/echo-client-consumer" build --scratch-path "$scratch_path/echo-client-consumer"

# AccessibilitySnapshot is UIKit-only. Building this isolated external
# consumer for the simulator verifies that the public manifest exposes it only
# on iOS, without asking SwiftPM to build macOS-only public products.
write_consumer "$temporary_root/accessibility-consumer" AccessibilityPlugin
readonly simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
readonly simulator_triple="$(simulator_architecture)-apple-ios14.0-simulator"
run_swift_in "$temporary_root/accessibility-consumer" build \
    --scratch-path "$scratch_path/accessibility-consumer" \
    --sdk "$simulator_sdk" \
    --triple "$simulator_triple"

printf '\nPublic build matrix passed.\n'
