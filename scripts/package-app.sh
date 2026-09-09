#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${DESKANCHOR_VERSION:-0.1.2}"
BUILD_NUMBER="${DESKANCHOR_BUILD:-1}"
SIGN_IDENTITY="${DESKANCHOR_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${DESKANCHOR_NOTARY_PROFILE:-}"
APP_DIR="$ROOT_DIR/.build/DeskAnchor.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
DMG_STAGING_DIR="$DMG_DIR/staging"
DIST_DIR="${DESKANCHOR_DIST_DIR:-$ROOT_DIR/dist}"
DMG_PATH="$DIST_DIR/DeskAnchor-$VERSION.dmg"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFT_TEMP_DIR="$ROOT_DIR/.build/tmp/swift-temp"
CLANG_CACHE_DIR="$ROOT_DIR/.build/tmp/clang-module-cache"

cd "$ROOT_DIR"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 1; }
if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "Notarization requires a Developer ID Application signing identity." >&2
    exit 1
fi
mkdir -p "$SWIFT_TEMP_DIR" "$CLANG_CACHE_DIR"
# Build each slice separately so this also works with Command Line Tools.
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0" \
        -Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=/DeskAnchor"
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
ARM_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)"
INTEL_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)"
lipo -create "$ARM_BIN_DIR/DeskAnchor" "$INTEL_BIN_DIR/DeskAnchor" -output "$MACOS_DIR/DeskAnchor"
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
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
</dict>
</plist>
PLIST

sed -i '' \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$CONTENTS_DIR/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
    echo "Development build: ad-hoc signed, not notarized." >&2
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_ZIP="$ROOT_DIR/.build/DeskAnchor-notarization.zip"
    ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    spctl --assess --type execute --verbose=2 "$APP_DIR"
fi

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

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi
(cd "$DIST_DIR" && shasum -a 256 "DeskAnchor-$VERSION.dmg" > "DeskAnchor-$VERSION.dmg.sha256")

echo "App bundle: $APP_DIR"
echo "Disk image: $DMG_PATH"
