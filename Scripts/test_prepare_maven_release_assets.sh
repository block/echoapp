#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
script="$root/prepare_maven_release_assets.sh"
fixture=$(mktemp -d)
cleanup() {
  for home in "$fixture/release-gnupg" "$fixture/foreign-gnupg"; do
    [[ ! -d $home ]] || gpgconf --homedir "$home" --kill all >/dev/null 2>&1 || true
  done
  rm -rf "$fixture"
}
trap cleanup EXIT
version=1.2.3+build.7
base="$fixture/repository/xyz/block/echoapp"

generate_signing_key() {
  local home=$1 identity=$2
  mkdir -p "$home"
  chmod 700 "$home"
  gpg --homedir "$home" --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$identity" rsa2048 sign 1d
  gpg --homedir "$home" --batch --with-colons --fingerprint |
    awk -F: '$1 == "fpr" {print $10; exit}'
}

sign_repository() {
  local repository=$1 home=$2
  for module in echo-client echo-plugin-api; do
    for artifact in "$repository/xyz/block/echoapp/$module/$version"/*; do
      gpg --homedir "$home" --batch --quiet --yes --armor --detach-sign \
        --pinentry-mode loopback --passphrase '' --output "$artifact.asc" "$artifact"
    done
  done
}

for module in echo-client echo-plugin-api; do
  dir="$base/$module/$version"
  mkdir -p "$dir"
  for suffix in aar pom module sources.jar javadoc.jar; do
    : > "$dir/$module-$version${suffix:+.$suffix}"
  done
  mv "$dir/$module-$version.sources.jar" "$dir/$module-$version-sources.jar"
  mv "$dir/$module-$version.javadoc.jar" "$dir/$module-$version-javadoc.jar"
  cat > "$dir/$module-$version.pom" <<EOF
<project><groupId>xyz.block.echoapp</groupId><artifactId>$module</artifactId><version>$version</version></project>
EOF
  dependencies='[]'
  [[ $module == echo-client ]] && dependencies="[{\"group\":\"xyz.block.echoapp\",\"module\":\"echo-plugin-api\",\"version\":{\"requires\":\"$version\"}}]"
  printf '{"component":{"group":"xyz.block.echoapp","module":"%s","version":"%s"},"variants":[{"dependencies":%s}]}' "$module" "$version" "$dependencies" > "$dir/$module-$version.module"
done

"$script" "$fixture/repository" "$version" "$fixture/output"
test "$(find "$fixture/output" -name '*.sha256' | wc -l | tr -d ' ')" = 10
test "$(wc -l < "$fixture/output/SHA256SUMS" | tr -d ' ')" = 10
grep -Fq "echo-client-$version.aar" "$fixture/output/SHA256SUMS"
grep -Fq "echo-plugin-api-$version-javadoc.jar" "$fixture/output/SHA256SUMS"
mkdir "$fixture/no-xmllint"
printf '#!/usr/bin/env bash\nexit 99\n' > "$fixture/no-xmllint/xmllint"
chmod +x "$fixture/no-xmllint/xmllint"
PATH="$fixture/no-xmllint:$PATH" "$script" "$fixture/repository" "$version" "$fixture/xml-portable-output"
if REQUIRE_SIGNATURES=true "$script" "$fixture/repository" "$version" "$fixture/unsigned-rejected" >/dev/null 2>&1; then
  echo "unsigned release unexpectedly passed the signed-release gate" >&2
  exit 1
fi

mkdir "$fixture/signed"
cp -R "$fixture/repository/." "$fixture/signed/"
release_home="$fixture/release-gnupg"
release_fingerprint=$(generate_signing_key "$release_home" 'EchoApp release test')
release_key=$(gpg --homedir "$release_home" --batch --armor --export "$release_fingerprint")
sign_repository "$fixture/signed" "$release_home"
ECHOAPP_RELEASE_GPG_KEY="$release_key" \
  ECHOAPP_RELEASE_GPG_FINGERPRINT="$release_fingerprint" \
  REQUIRE_SIGNATURES=true "$script" "$fixture/signed" "$version" "$fixture/signed-output"
test "$(wc -l < "$fixture/signed-output/SHA256SUMS" | tr -d ' ')" = 20

mkdir "$fixture/bad-signature"
cp -R "$fixture/signed/." "$fixture/bad-signature/"
printf 'tampered' >> "$fixture/bad-signature/xyz/block/echoapp/echo-client/$version/echo-client-$version.aar"
if ECHOAPP_RELEASE_GPG_KEY="$release_key" \
    ECHOAPP_RELEASE_GPG_FINGERPRINT="$release_fingerprint" \
    REQUIRE_SIGNATURES=true "$script" "$fixture/bad-signature" "$version" "$fixture/bad-output" >/dev/null 2>&1; then
  echo "tampered signed artifact unexpectedly passed" >&2
  exit 1
fi

foreign_home="$fixture/foreign-gnupg"
foreign_fingerprint=$(generate_signing_key "$foreign_home" 'EchoApp foreign test')
foreign_key=$(gpg --homedir "$foreign_home" --batch --armor --export "$foreign_fingerprint")
mkdir "$fixture/foreign-signature"
cp -R "$fixture/signed/." "$fixture/foreign-signature/"
foreign_artifact="$fixture/foreign-signature/xyz/block/echoapp/echo-client/$version/echo-client-$version.aar"
gpg --homedir "$foreign_home" --batch --quiet --yes --armor --detach-sign \
  --pinentry-mode loopback --passphrase '' --output "$foreign_artifact.asc" "$foreign_artifact"
combined_keys="$release_key"$'\n'"$foreign_key"
if ECHOAPP_RELEASE_GPG_KEY="$combined_keys" \
    ECHOAPP_RELEASE_GPG_FINGERPRINT="$release_fingerprint" \
    REQUIRE_SIGNATURES=true "$script" "$fixture/foreign-signature" "$version" "$fixture/foreign-output" >/dev/null 2>&1; then
  echo "foreign-key signature unexpectedly passed" >&2
  exit 1
fi

mkdir "$fixture/partial"
cp -R "$fixture/repository/." "$fixture/partial/"
: > "$fixture/partial/xyz/block/echoapp/echo-client/$version/echo-client-$version.aar.asc"
if "$script" "$fixture/partial" "$version" "$fixture/rejected" >/dev/null 2>&1; then
  echo "partial signatures unexpectedly passed" >&2
  exit 1
fi

for leaked_dependency in \
  sealed-swift-compat-codegen \
  sealed-swift-compat-proguard-rule-gen; do
  printf -v leaked_group '%s.%s.%s' com squareup moshix
  leaked_fixture="$fixture/leaked-$leaked_dependency"
  mkdir "$leaked_fixture"
  cp -R "$fixture/repository/." "$leaked_fixture/"
  leaked_module="$leaked_fixture/xyz/block/echoapp/echo-plugin-api/$version/echo-plugin-api-$version.module"
  jq --arg group "$leaked_group" --arg dependency "$leaked_dependency" \
    '.variants[0].dependencies += [{"group":$group,"module":$dependency,"version":{"requires":"0.1.0-alpha3"}}]' \
    "$leaked_module" > "$leaked_module.tmp"
  mv "$leaked_module.tmp" "$leaked_module"
  leak_error="$fixture/leak-error-$leaked_dependency"
  if "$script" "$leaked_fixture" "$version" "$leaked_fixture-output" >/dev/null 2>"$leak_error"; then
    echo "$leaked_dependency metadata unexpectedly passed" >&2
    exit 1
  fi
  grep -Fq 'build-only dependency leaked into echo-plugin-api metadata' "$leak_error"
done

mkdir "$fixture/wrong-pom"
cp -R "$fixture/repository/." "$fixture/wrong-pom/"
cat > "$fixture/wrong-pom/xyz/block/echoapp/echo-client/$version/echo-client-$version.pom" <<EOF
<project><groupId>invalid.example</groupId><artifactId>echo-client</artifactId><version>$version</version></project>
EOF
if "$script" "$fixture/wrong-pom" "$version" "$fixture/wrong-pom-output" >/dev/null 2>&1; then
  echo "wrong POM identity unexpectedly passed" >&2
  exit 1
fi

echo "prepare_maven_release_assets tests passed"
