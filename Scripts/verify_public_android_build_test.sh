#!/usr/bin/env bash
# Static regression assertions for public Android dependency isolation.

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly verification_script="$script_dir/verify_public_android_build.sh"

require() {
    local expression="$1"
    if ! grep -Fq -- "$expression" "$verification_script"; then
        echo "Missing public Android build isolation: $expression" >&2
        exit 1
    fi
}

require '[[ "$repository_root" != "$public_root" ]]'
require 'git -C "$public_root" archive HEAD'
require 'env -i'
require 'GRADLE_USER_HOME="$temporary_gradle_home_path"'
require 'HOME="$temporary_home_path"'
require 'JAVA_HOME="$configured_java_home_path"'
require 'PATH="$configured_path"'
require '--refresh-dependencies build'
require 'publishToMavenLocal'
require 'prepare_maven_release_assets.sh'

if grep -Eq 'archive HEAD:[^ ]+' "$verification_script"; then
    echo "Public Android verifier archives a repository subdirectory." >&2
    exit 1
fi

printf 'Public Android build isolation assertions passed.\n'
