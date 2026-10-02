#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
configuration="${CONFIGURATION:-debug}"
xcrun swift build --disable-sandbox -c "$configuration" --product Winnel
xcrun swift build --disable-sandbox -c "$configuration" --product WinnelFixture
bin_path=$(xcrun swift build --disable-sandbox -c "$configuration" --show-bin-path)
mkdir -p build
xcrun swift scripts/make-icon.swift "$PWD/build/Winnel.iconset"
/usr/bin/iconutil -c icns "$PWD/build/Winnel.iconset" -o "$PWD/build/Winnel.icns"
for product in Winnel WinnelFixture; do
  app_path="$PWD/build/$product.app"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cp "$bin_path/$product" "$app_path/Contents/MacOS/$product"
  cp "$PWD/build/Winnel.icns" "$app_path/Contents/Resources/Winnel.icns"
  cp "$PWD/LICENSE" "$app_path/Contents/Resources/LICENSE.txt"
  bundle_id="org.madeordinary.winnel"
  agent_app='<true/>'
  if [ "$product" = WinnelFixture ]; then bundle_id="org.madeordinary.winnel.fixture"; agent_app='<false/>'; fi
  cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$product</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>$product</string>
<key>CFBundleDisplayName</key><string>$product</string>
<key>CFBundleIconFile</key><string>Winnel.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key>$agent_app
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Made Ordinary. MIT.</string>
</dict></plist>
PLIST
  /usr/bin/codesign --force --sign - "$app_path"
  /usr/bin/codesign --verify --strict "$app_path"
done
printf 'Built ad-hoc development bundles in %s/build\n' "$PWD"
