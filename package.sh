#!/bin/bash
# Builds the app and packages it for download: build/WheredItGo.zip
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

ZIP="build/WheredItGo.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Where'd It Go.app" "$ZIP"
echo "Packaged $ZIP"
