#!/bin/bash
# Builds a signed installer package for the Mac App Store: build/WheredItGo.pkg
# Upload it to App Store Connect with Apple's Transporter app.
#
# Needs, from an Apple Developer Program membership:
#   TEAM_ID             your 10-character team ID
#   APP_IDENTITY        "Apple Distribution: Name (TEAM_ID)" or "3rd Party Mac Developer Application: Name (TEAM_ID)"
#   INSTALLER_IDENTITY  "3rd Party Mac Developer Installer: Name (TEAM_ID)"
#   PROFILE             a Mac App Store provisioning profile for app.whereditgo.mac
set -euo pipefail
cd "$(dirname "$0")"

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
: "${APP_IDENTITY:?Set APP_IDENTITY to your Apple Distribution signing identity}"
: "${INSTALLER_IDENTITY:?Set INSTALLER_IDENTITY to your Mac Installer Distribution identity}"
: "${PROFILE:?Set PROFILE to your Mac App Store provisioning profile}"

./build.sh release

APP="build/Where'd It Go.app"
PKG="build/WheredItGo.pkg"
ENTITLEMENTS="build/appstore.entitlements"

cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
cp Resources/WheredItGo.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.application-identifier string $TEAM_ID.app.whereditgo.mac" \
  -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
  "$ENTITLEMENTS"

codesign --force --sign "$APP_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
echo "Packaged $PKG"
