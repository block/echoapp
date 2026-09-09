#!/usr/bin/env bash
# Builds the immutable, reviewable Android release bundle from a Maven repository
# produced by Gradle. It never publishes and it never invokes GitHub.
set -euo pipefail

if [[ $# != 3 ]]; then
  echo "usage: $0 <maven-repository> <version> <output-directory>" >&2
  exit 64
fi

repository=$1
version=$2
output=$3
script_dir=$(cd "$(dirname "$0")" && pwd)
group_path=xyz/block/echoapp
modules=(echo-client echo-plugin-api)
verification_home=
expected_fingerprint=

fail() { echo "error: $*" >&2; exit 1; }
cleanup() {
  if [[ -n $verification_home ]]; then
    gpgconf --homedir "$verification_home" --kill all >/dev/null 2>&1 || true
    rm -rf "$verification_home"
  fi
}
trap cleanup EXIT

initialize_signature_verifier() {
  [[ -n $verification_home ]] && return
  command -v gpg >/dev/null || fail "gpg is required to verify detached signatures"
  expected_fingerprint=$(printf '%s' "${ECHOAPP_RELEASE_GPG_FINGERPRINT:-}" | tr '[:lower:]' '[:upper:]')
  [[ $expected_fingerprint =~ ^([A-F0-9]{40}|[A-F0-9]{64})$ ]] ||
    fail "ECHOAPP_RELEASE_GPG_FINGERPRINT must be a full OpenPGP fingerprint"
  [[ -n ${ECHOAPP_RELEASE_GPG_KEY:-} ]] || fail "ECHOAPP_RELEASE_GPG_KEY is required for signed artifacts"
  verification_home=$(mktemp -d)
  chmod 700 "$verification_home"
  printf '%s\n' "$ECHOAPP_RELEASE_GPG_KEY" |
    gpg --homedir "$verification_home" --batch --quiet --import 2>/dev/null ||
    fail "could not import the EchoApp release key"
}

verify_signature() {
  local artifact=$1 signature=$2 status fingerprints
  status=$(gpg --homedir "$verification_home" --batch --status-fd 1 \
    --verify "$signature" "$artifact" 2>/dev/null) || fail "invalid detached signature: $(basename "$signature")"
  fingerprints=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print toupper($3); print toupper($NF)}' <<< "$status")
  grep -Fqx "$expected_fingerprint" <<< "$fingerprints" ||
    fail "detached signature uses an unexpected release key: $(basename "$signature")"
}

validate_pom() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
values = {child.tag.rsplit("}", 1)[-1]: (child.text or "").strip() for child in root}
if (values.get("groupId"), values.get("artifactId"), values.get("version")) != (
    "xyz.block.echoapp", sys.argv[2], sys.argv[3]
):
    raise SystemExit(1)
PY
}

canonical_version="$($script_dir/release_version.sh "$version")" || fail "invalid Android version: $version"
[[ $version == "$canonical_version" ]] || fail "Android version must be canonical SemVer: $version"
[[ -d $repository ]] || fail "Maven repository does not exist: $repository"
[[ ! -e $output ]] || fail "output directory already exists: $output"
mkdir -p "$output"

for module in "${modules[@]}"; do
  source_dir="$repository/$group_path/$module/$version"
  destination="$output/$group_path/$module/$version"
  [[ -d $source_dir ]] || fail "missing $module $version in Maven repository"

  artifacts=(
    "$module-$version.aar"
    "$module-$version.pom"
    "$module-$version.module"
    "$module-$version-sources.jar"
    "$module-$version-javadoc.jar"
  )
  signatures=0
  for artifact in "${artifacts[@]}"; do
    [[ -f $source_dir/$artifact ]] || fail "missing $module artifact: $artifact"
    if [[ -f $source_dir/$artifact.asc ]]; then
      ((signatures += 1))
    fi
  done
  [[ $signatures == 0 || $signatures == ${#artifacts[@]} ]] || fail "partial detached signatures for $module"
  [[ ${REQUIRE_SIGNATURES:-false} != true || $signatures == ${#artifacts[@]} ]] || fail "missing detached signatures for $module"
  if (( signatures > 0 )); then
    initialize_signature_verifier
    for artifact in "${artifacts[@]}"; do
      verify_signature "$source_dir/$artifact" "$source_dir/$artifact.asc"
    done
  fi

  expected="$({
    printf '%s\n' "${artifacts[@]}"
    for artifact in "${artifacts[@]}"; do
      if [[ -f $source_dir/$artifact.asc ]]; then
        printf '%s.asc\n' "$artifact"
      fi
    done
  } | LC_ALL=C sort)"
  actual="$(find "$source_dir" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)"
  [[ $actual == "$expected" ]] || fail "unexpected artifact inventory for $module: expected [$expected], got [$actual]"

  pom="$source_dir/$module-$version.pom"
  gradle_module="$source_dir/$module-$version.module"
  validate_pom "$pom" "$module" "$version" || fail "wrong POM identity for $module"
  jq -e --arg module "$module" --arg version "$version" \
    '.component.group == "xyz.block.echoapp" and .component.module == $module and .component.version == $version' \
    "$gradle_module" >/dev/null || fail "wrong Gradle metadata identity for $module"
  if grep -Fiq 'sealed-swift-compat-' "$pom" "$gradle_module"; then
    fail "build-only dependency leaked into $module metadata"
  fi
  if [[ $module == echo-client ]]; then
    jq -e --arg version "$version" \
      '[.variants[].dependencies[]? | select(.group == "xyz.block.echoapp" and .module == "echo-plugin-api" and .version.requires == $version)] | length > 0' \
      "$gradle_module" >/dev/null || fail "echo-client metadata does not require echo-plugin-api $version"
  fi
  mkdir -p "$destination"
  cp "$source_dir"/* "$destination/"
done

manifest="$output/SHA256SUMS"
while IFS= read -r artifact; do
  hash="$(shasum -a 256 "$output/$artifact" | awk '{print $1}')"
  printf '%s  %s\n' "$hash" "$artifact" >> "$manifest"
  printf '%s  %s\n' "$hash" "$(basename "$artifact")" > "$output/$artifact.sha256"
done < <(cd "$output" && find "$group_path" -type f | LC_ALL=C sort)

echo "Prepared $(wc -l < "$manifest" | tr -d ' ') Android release artifacts at $output"
