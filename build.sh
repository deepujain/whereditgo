#!/bin/bash
# Builds "Where'd It Go.app" into ./build, signed ad hoc for local use.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Where'd It Go.app"
CONFIG="${1:-release}"

swift build -c "$CONFIG" --product WheredItGo
BIN="$(swift build -c "$CONFIG" --show-bin-path)/WheredItGo"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WheredItGo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime --timestamp=none "$APP"
echo "Built $APP"
