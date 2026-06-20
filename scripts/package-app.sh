#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${DESKANCHOR_VERSION:-0.1.0}"
BUILD_NUMBER="${DESKANCHOR_BUILD:-1}"
APP_DIR="$ROOT_DIR/.build/DeskAnchor.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
DMG_STAGING_DIR="$DMG_DIR/staging"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/DeskAnchor-$VERSION.dmg"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFT_TEMP_DIR="$ROOT_DIR/.build/tmp/swift-temp"
CLANG_CACHE_DIR="$ROOT_DIR/.build/tmp/clang-module-cache"

cd "$ROOT_DIR"
mkdir -p "$SWIFT_TEMP_DIR" "$CLANG_CACHE_DIR"
swift build -c release \
    -Xswiftc -debug-prefix-map \
    -Xswiftc "$ROOT_DIR=/DeskAnchor"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/DeskAnchor" "$MACOS_DIR/DeskAnchor"
strip -x "$MACOS_DIR/DeskAnchor"
TMPDIR="$SWIFT_TEMP_DIR" CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
    swift scripts/generate-app-icon.swift "$RESOURCES_DIR/DeskAnchor.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DeskAnchor</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.deskanchor</string>
    <key>CFBundleName</key>
    <string>DeskAnchor</string>
    <key>CFBundleDisplayName</key>
    <string>DeskAnchor</string>
    <key>CFBundleIconFile</key>
    <string>DeskAnchor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__BUILD_NUMBER__</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
</dict>
</plist>
PLIST

sed -i '' \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$DIST_DIR" "$DMG_DIR"
rm -rf "$DMG_STAGING_DIR" "$DMG_PATH" "$DIST_DIR/DeskAnchor.app"
mkdir -p "$DMG_STAGING_DIR"
ditto --norsrc --noextattr "$APP_DIR" "$DMG_STAGING_DIR/DeskAnchor.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

COPYFILE_DISABLE=1 hdiutil create \
    -volname "DeskAnchor" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "App bundle: $APP_DIR"
echo "Disk image: $DMG_PATH"
