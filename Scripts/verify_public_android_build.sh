#!/usr/bin/env bash
# Verifies that the public Android source and Maven artifacts need only public
# dependency repositories and do not expose EchoApp's embedded build tools.

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly public_root="$(cd "$script_dir/.." && pwd -P)"
readonly temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/echo-public-android.XXXXXX")"
readonly release_root="$temporary_root/echo"
readonly temporary_home_path="$temporary_root/home"
readonly temporary_gradle_home_path="$temporary_root/gradle-home"
readonly temporary_maven_repository_path="$temporary_root/maven-local"
readonly release_assets_path="$temporary_root/release-assets"
readonly configured_android_sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
readonly configured_java_home_path="${JAVA_HOME:-}"
readonly configured_lang="${LANG:-C.UTF-8}"
readonly configured_path="${PATH:?PATH must be set}"
readonly configured_tmpdir_path="${TMPDIR:-/tmp}"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

if [[ -z "$configured_android_sdk_path" || ! -d "$configured_android_sdk_path" ]]; then
    echo "Set ANDROID_HOME or ANDROID_SDK_ROOT to an installed Android SDK." >&2
    exit 1
fi

archive_public_tree() {
    local repository_root
    repository_root="$(git -C "$public_root" rev-parse --show-toplevel)"

    if [[ "$repository_root" != "$public_root" ]]; then
        echo "Run this verifier from a standalone checkout of the public repository." >&2
        exit 1
    fi

    mkdir -p "$release_root"
    git -C "$public_root" archive HEAD | tar -xf - -C "$release_root"
    [[ ! -e "$release_root/.git" ]]
}

run_gradle() {
    mkdir -p "$temporary_home_path"
    env -i \
        ANDROID_HOME="$configured_android_sdk_path" \
        ANDROID_SDK_ROOT="$configured_android_sdk_path" \
        GRADLE_USER_HOME="$temporary_gradle_home_path" \
        HOME="$temporary_home_path" \
        JAVA_HOME="$configured_java_home_path" \
        LANG="$configured_lang" \
        PATH="$configured_path" \
        TMPDIR="$configured_tmpdir_path" \
        "$release_root/android/gradlew" -p "$release_root/android" --no-daemon "$@"
}

archive_public_tree

run_gradle --refresh-dependencies build

readonly version="$(sed -n 's/^VERSION_NAME=//p' "$release_root/android/gradle.properties")"
run_gradle -Dmaven.repo.local="$temporary_maven_repository_path" \
    -PVERSION_NAME="$version" \
    -PRELEASE_SIGNING_ENABLED=false \
    publishToMavenLocal

"$release_root/Scripts/prepare_maven_release_assets.sh" \
    "$temporary_maven_repository_path" "$version" "$release_assets_path"

printf '\nPublic Android build and Maven metadata verification passed.\n'
