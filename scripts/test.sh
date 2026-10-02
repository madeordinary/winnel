#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Xcode27 SwiftBuild stamps SDK14.0 here; native SwiftPM records the selected SDK correctly.
winnel_sdk_path=$(xcrun --sdk macosx --show-sdk-path)
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
exec xcrun swift test --build-system native --sdk "$winnel_sdk_path" --disable-sandbox "$@"
