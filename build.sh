#!/bin/bash
# Builds Closed-Lid Mode.app from src/main.swift.
#   ./build.sh            -> builds into ./build
#   ./build.sh --install  -> builds, then installs to /Applications and launches
set -euo pipefail

APP_NAME="Closed-Lid Mode"
BUNDLE_ID="io.github.saarukesh2005.closedlidmode"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build/$APP_NAME.app"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

echo "Compiling..."
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
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# LSUIElement keeps it out of the Dock; the ad-hoc signature lets it launch.
codesign --force --sign - --timestamp=none "$OUT" >/dev/null 2>&1
echo "Built: $OUT"

if [[ "${1:-}" == "--install" ]]; then
    pkill -f "$APP_NAME.app/Contents/MacOS/ClosedLidMode" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$OUT" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "Installed to /Applications and launched."
    echo "Look for a red or green dot in your menu bar."
fi
