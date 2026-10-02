#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-$PWD/build/evidence/diagnostics}"
if [[ "$output" != "$PWD/build/"* ]]; then
  printf 'Diagnostics output must be an absolute directory beneath %s/build/\n' "$PWD" >&2
  exit 2
fi
mkdir -p "$output"
app="$PWD/build/Winnel.app/Contents/MacOS/Winnel"
if [[ ! -x "$app" ]]; then
  printf 'Build the local app first with bash scripts/build.sh\n' >&2
  exit 2
fi
"$app" --diagnostics "$output"
printf 'Actual-view render diagnostics: %s/diagnostics.json\n' "$output"
