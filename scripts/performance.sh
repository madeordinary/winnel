#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Xcode27 SwiftBuild stamps SDK14.0 here; native SwiftPM records the selected SDK correctly.
winnel_sdk_path=$(xcrun --sdk macosx --show-sdk-path)
export CLANG_MODULE_CACHE_PATH="$PWD/.build-performance/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-performance/module-cache"
output_directory="${1:-$PWD/build/performance-$(date -u +%Y%m%dT%H%M%SZ)}"
idle_seconds="${IDLE_SECONDS:-1800}"
xcrun swift build --build-system native --sdk "$winnel_sdk_path" --disable-sandbox -c release --scratch-path "$PWD/.build-performance" --product Winnel
bin_path=$(xcrun swift build --build-system native --sdk "$winnel_sdk_path" --disable-sandbox -c release --scratch-path "$PWD/.build-performance" --show-bin-path)
case "$output_directory" in "$PWD"/build/*) ;; *) printf 'Performance output must be an absolute project build subdirectory.\n' >&2; exit 2;; esac
mkdir -p "$output_directory"
cp "$bin_path/Winnel" "$output_directory/Winnel-benchmark"
shasum -a 256 "$output_directory/Winnel-benchmark" > "$output_directory/binary-sha256.txt"
while IFS= read -r source_file; do shasum -a 256 "$source_file"; done < <(rg --files Sources | sort) > "$output_directory/source-sha256.txt"
xcrun swift --version > "$output_directory/swift-version.txt"
xcodebuild -version > "$output_directory/xcode-version.txt"
exec "$output_directory/Winnel-benchmark" --performance "$output_directory" --idle-seconds "$idle_seconds"
