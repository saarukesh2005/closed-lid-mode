#!/bin/bash
# Build Closed-Lid Mode.app
#
#   ./build.sh             build into ./build
#   ./build.sh --install   build, install to /Applications, launch
#   ./build.sh --release   build, then package a .zip and a .dmg for release
set -euo pipefail

APP_NAME="Closed-Lid Mode"
BUNDLE_ID="io.github.saarukesh2005.closedlidmode"
# Overridable so CI can stamp the git tag: VERSION=1.2.3 ./build.sh --release
VERSION="${VERSION:-1.0.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
OUT="$BUILD/$APP_NAME.app"

command -v swiftc >/dev/null || {
    echo "swiftc not found. Install the Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
}

mkdir -p "$BUILD"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "==> Icon"
swift "$HERE/tools/make-icon.swift" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
cp "$BUILD/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"

echo "==> Compile"
swiftc -swift-version 5 -O -o "$OUT/Contents/MacOS/ClosedLidMode" \
    "$HERE/src/main.swift" -framework Cocoa

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>ClosedLidMode</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. This is NOT a Developer ID signature and the app is not
# notarised - see the Gatekeeper section of the README.
codesign --force --sign - --timestamp=none "$OUT" >/dev/null 2>&1
echo "==> Built: $OUT"

case "${1:-}" in
--install)
    pkill -f "$APP_NAME.app/Contents/MacOS/ClosedLidMode" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$OUT" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    # Remove the staging copy. Leaving a second .app on disk gets it indexed
    # by Spotlight and Launchpad, and makes it far too easy to launch a
    # second instance by accident - two menu bar icons, one of them stale.
    rm -rf "$OUT"
    echo "==> Installed to /Applications and launched."
    echo "    Look for a red or green dot in your menu bar."
    ;;
--release)
    ZIP="$BUILD/ClosedLidMode-$VERSION.zip"
    DMG="$BUILD/ClosedLidMode-$VERSION.dmg"
    rm -f "$ZIP" "$DMG"

    # ditto, not zip: it preserves the bundle's metadata and signature.
    ditto -c -k --sequesterRsrc --keepParent "$OUT" "$ZIP"
    echo "==> $ZIP"

    STAGE="$BUILD/dmg-stage"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$OUT" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" \
        -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "==> $DMG"
    # Same reason as --install: ship the .zip and .dmg, never leave a loose
    # .app lying around to be indexed and double-launched.
    rm -rf "$OUT"
    ;;
esac
