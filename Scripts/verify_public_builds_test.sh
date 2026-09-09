#!/usr/bin/env bash
# Static regression assertions for public-build credential and cache isolation.

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly matrix_script="$script_dir/verify_public_builds.sh"

require() {
    local expression="$1"
    if ! grep -Fq -- "$expression" "$matrix_script"; then
        echo "Missing public-build isolation: $expression" >&2
        exit 1
    fi
}

# Git and HTTPS must not inherit login config, default SSH keys, or ~/.netrc.
require 'HOME="$temporary_home_path"'
require 'NETRC="$temporary_home_path/.netrc"'
require ': > "$temporary_home_path/.netrc"'
require '-u SWIFTPM_MIRROR_CONFIG'
require '-u SWIFTPM_REGISTRY_TOKEN'
require '-u SWIFTPM_SOURCE_CONTROL_TOKEN'
require 'GIT_CONFIG_NOSYSTEM=1'
require 'GIT_CONFIG_GLOBAL=/dev/null'
require 'GIT_CONFIG_KEY_0=credential.helper'
require 'GIT_TERMINAL_PROMPT=0'
require 'IdentityFile=none'
require 'IdentityAgent=none'
require 'SSH_AUTH_SOCK=/dev/null'
require '[[ "$repository_root" != "$public_root" ]]'
require 'git -C "$public_root" archive HEAD'

if grep -Eq 'archive HEAD:[^ ]+' "$matrix_script"; then
    echo "Public build verifier archives a repository subdirectory." >&2
    exit 1
fi

# Every SwiftPM invocation runs through the isolated environment and passes
# dedicated cache, configuration, and security locations.
require 'run_with_isolated_credentials "$@"'
require 'xcrun swift "$@" \'
require '--cache-path "$swiftpm_cache_path"'
require '--config-path "$swiftpm_config_path"'
require '--security-path "$swiftpm_security_path"'
require '--disable-keychain'
require '--enable-netrc'
require '--netrc-file "$temporary_home_path/.netrc"'

# Xcode must use the hardened system Git provider plus isolated resolver state.
require '-scmProvider system'
require '-clonedSourcePackagesDirPath "$cloned_source_packages_path"'
require '-packageCachePath "$xcode_package_cache_path"'

printf 'Public build isolation assertions passed.\n'
