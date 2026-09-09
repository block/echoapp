#!/bin/bash

set -euo pipefail

archive_path=""
version=""
repo_root="$(git rev-parse --show-toplevel)"
source_root="${ECHOAPP_SOURCE_ROOT:-$repo_root}"
project_path="$source_root/App/App.xcodeproj"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive-path)
            archive_path="$2"
            shift
            ;;
        --version)
            version="$2"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$archive_path" ]]; then
    echo "The --archive-path argument is required"
    exit 1
fi

release_version="0.0.0-dev"
if [[ -n "$version" ]]; then
    release_version="$("$source_root/Scripts/release_version.sh" "$version")"
fi
marketing_version="${release_version%%-*}"
marketing_version="${marketing_version%%+*}"
build_number="$(date +%Y.%m%d.%H%M)"

sed -i "" "s/MARKETING_VERSION = .*/MARKETING_VERSION = $marketing_version;/g" "$project_path/project.pbxproj"
sed -i "" "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_path/project.pbxproj"
# Xcode's OpenStep project format requires SemVer build metadata to be quoted.
sed -i "" "s/ECHOAPP_RELEASE_VERSION = .*/ECHOAPP_RELEASE_VERSION = \"$release_version\";/g" "$project_path/project.pbxproj"

cli_plist="$source_root/EchoApp/Sources/EchoCLI/Resources/Version.plist"
if [[ -f "$cli_plist" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$cli_plist"
fi

set -x
xcodebuild \
    clean \
    archive \
    DEBUG_INFORMATION_FORMAT=DWARF \
    STRIP_STYLE=non-global \
    STRIP_INSTALLED_PRODUCT=NO \
    -archivePath "$archive_path" \
    -configuration "Release" \
    -destination "generic/platform=macOS" \
    -project "$project_path" \
    -scheme "Echo"
set +x
