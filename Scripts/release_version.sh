#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <semver-or-v-prefixed-semver>" >&2
    exit 64
fi

release_version="${1#v}"
semver_pattern='^((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$release_version" =~ $semver_pattern ]]; then
    echo "EchoApp release version must be Semantic Versioning 2.0.0: $1" >&2
    exit 64
fi

precedence_version="${release_version%%+*}"
if [[ "$precedence_version" == *-* ]]; then
    while IFS= read -r identifier; do
        if [[ "$identifier" =~ ^0[0-9]+$ ]]; then
            echo "EchoApp prerelease numeric identifiers cannot contain leading zeroes: $1" >&2
            exit 64
        fi
    done < <(tr '.' '\n' <<< "${precedence_version#*-}")
fi

printf '%s\n' "$release_version"
