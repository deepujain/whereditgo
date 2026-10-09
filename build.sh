#!/bin/bash
# Builds "Where'd It Go.app" into ./build, signed ad hoc for local use.
# Release builds are universal (Apple silicon and Intel); debug builds are for this Mac only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Where'd It Go.app"
CONFIG="${1:-release}"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin

# Both architectures build into the same folder, so keep each binary as it is built.
swift build -c "$CONFIG" --product WheredItGo
BIN=build/bin/WheredItGo-native
cp "$(swift build -c "$CONFIG" --show-bin-path)/WheredItGo" "$BIN"
if [ "$CONFIG" = release ]; then
  INTEL=x86_64-apple-macosx14.0
  swift build -c release --product WheredItGo --triple "$INTEL"
  cp "$(swift build -c release --triple "$INTEL" --show-bin-path)/WheredItGo" build/bin/WheredItGo-x86_64
  lipo -create "$BIN" build/bin/WheredItGo-x86_64 -output "$APP/Contents/MacOS/WheredItGo"
else
  cp "$BIN" "$APP/Contents/MacOS/WheredItGo"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"

"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime --timestamp=none "$APP"
echo "Built $APP"
