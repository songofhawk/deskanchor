#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${WINSTORE_VERSION:-0.1.0}"
BUILD_NUMBER="${WINSTORE_BUILD:-1}"
APP_DIR="$ROOT_DIR/.build/Winstore.app"
PKG_DIR="$ROOT_DIR/.build/package"
PKG_PATH="$PKG_DIR/Winstore-$VERSION.pkg"
PKG_ROOT="$PKG_DIR/root"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/Winstore" "$MACOS_DIR/Winstore"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Winstore</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.winstore</string>
    <key>CFBundleName</key>
    <string>Winstore</string>
    <key>CFBundleDisplayName</key>
    <string>Winstore</string>
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

mkdir -p "$PKG_DIR"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
ditto --norsrc --noextattr "$APP_DIR" "$PKG_ROOT/Applications/Winstore.app"

COPYFILE_DISABLE=1 pkgbuild \
    --identifier "dev.local.winstore.pkg" \
    --version "$VERSION" \
    --root "$PKG_ROOT" \
    --install-location "/" \
    "$PKG_PATH"

echo "App bundle: $APP_DIR"
echo "Installer: $PKG_PATH"
