#!/bin/bash
# Build Closed-Lid Mode.app
#
#   ./build.sh             build into ./build
#   ./build.sh --test      run the test suite
#   ./build.sh --install   build, install to /Applications, launch
#   ./build.sh --release   build, then package a .zip and a .dmg
set -euo pipefail

APP_NAME="Closed-Lid Mode"
BUNDLE_ID="io.github.saarukesh2005.closedlidmode"
# Overridable so CI can stamp the git tag: VERSION=1.2.3 ./build.sh --release
VERSION="${VERSION:-1.2.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
OUT="$BUILD/$APP_NAME.app"

command -v swift >/dev/null || {
    echo "swift not found. Install the Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
}

cd "$HERE"

if [[ "${1:-}" == "--test" ]]; then
    exec swift run -c release ClosedLidModeTests
fi

mkdir -p "$BUILD"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "==> Tests"
swift run -c release ClosedLidModeTests

echo "==> Icon"
swift "$HERE/tools/make-icon.swift" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
cp "$BUILD/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"

echo "==> Compile"
swift build -c release --product ClosedLidMode
cp "$(swift build -c release --product ClosedLidMode --show-bin-path)/ClosedLidMode" \
   "$OUT/Contents/MacOS/ClosedLidMode"

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

# Ad-hoc signature. NOT a Developer ID signature and not notarised - see the
# Gatekeeper section of the README.
codesign --force --sign - --timestamp=none "$OUT" >/dev/null 2>&1
echo "==> Built: $OUT"

case "${1:-}" in
--install)
    pkill -f "$APP_NAME.app/Contents/MacOS/ClosedLidMode" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$OUT" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    # Leaving a second .app on disk gets it indexed by Spotlight and makes it
    # far too easy to launch a stray duplicate - two menu bar icons.
    rm -rf "$OUT"
    echo "==> Installed to /Applications and launched."
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
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE" "$OUT"
    echo "==> $DMG"
    ;;
esac
