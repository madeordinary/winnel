#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x /usr/bin/sandbox-exec ]]; then
  printf 'This macOS host does not provide sandbox-exec; offline process verification is unavailable.\n' >&2
  exit 2
fi
# Adds a restriction to this test process and its children only. No global network,
# privacy, signing or system security settings are changed.
exec /usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' /bin/bash scripts/test.sh "$@"
