#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Winnel.app ] || scripts/build.sh
open -n build/WinnelFixture.app
open -n build/Winnel.app --args --fixture
