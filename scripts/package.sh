#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION=release bash scripts/build.sh
output="$PWD/build/distribution"
mkdir -p "$output"
/usr/bin/codesign --verify --strict "$PWD/build/Winnel.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PWD/build/Winnel.app" "$output/Winnel-0.1.0-development.zip"
/usr/bin/shasum -a 256 "$output/Winnel-0.1.0-development.zip" > "$output/SHA256SUMS.txt"
git rev-parse HEAD > "$output/source-revision.txt"
git status --porcelain > "$output/source-working-tree.txt"
/usr/bin/codesign -dv --verbose=4 "$PWD/build/Winnel.app" 2> "$output/signature.txt"
printf 'Local ad-hoc development archive: %s/Winnel-0.1.0-development.zip\n' "$output"
