#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build-preview-performance/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-preview-performance/module-cache"
output_directory="${1:-$PWD/build/preview-performance-$(date -u +%Y%m%dT%H%M%SZ)}"
case "$output_directory" in "$PWD"/build/*) ;; *) printf 'Preview output must be an absolute project build subdirectory.\n' >&2; exit 2;; esac
xcrun swift build --disable-sandbox -c release --scratch-path "$PWD/.build-preview-performance" --product Winnel
bin_path=$(xcrun swift build --disable-sandbox -c release --scratch-path "$PWD/.build-preview-performance" --show-bin-path)
mkdir -p "$output_directory"
cp "$bin_path/Winnel" "$output_directory/Winnel-preview-benchmark"
shasum -a 256 "$output_directory/Winnel-preview-benchmark" > "$output_directory/binary-sha256.txt"
while IFS= read -r source_file; do shasum -a 256 "$source_file"; done < <(rg --files Sources | sort) > "$output_directory/source-sha256.txt"
xcrun swift --version > "$output_directory/swift-version.txt"
xcodebuild -version > "$output_directory/xcode-version.txt"
exec "$output_directory/Winnel-preview-benchmark" --preview-performance "$output_directory"
