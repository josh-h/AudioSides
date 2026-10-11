#!/bin/zsh
# Builds a Developer ID–signed, notarized and stapled AudioSides disk image (and zip) for download.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   2. Notary credentials saved under the profile name below:
#      xcrun notarytool store-credentials AudioSides --apple-id <you@example.com> --team-id <YOUR_TEAM_ID>
#
# Usage: APPLE_TEAM_ID=<YOUR_TEAM_ID> scripts/release.sh
#
# Signs with your Developer ID certificate from the start, so no development certificate
# or provisioning profile is needed. If you have more than one Developer ID certificate,
# pick one with SIGNING_IDENTITY set to its SHA-1 hash from
# `security find-identity -v -p codesigning`.
set -euo pipefail

# xcodebuild needs Xcode, not just the Command Line Tools. If xcode-select points at the
# Command Line Tools, use an installed Xcode for this run instead (no sudo needed).
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" != *.app/Contents/Developer ]]; then
  XCODE=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)
  [[ -n "$XCODE" ]] || { echo "Xcode isn't installed. Install Xcode 26 or later, then run this again."; exit 1; }
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
  echo "› Using $XCODE (xcode-select points at the Command Line Tools)"
fi

TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team ID.}"
PROFILE="${NOTARY_PROFILE:-AudioSides}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
ROOT="${0:A:h:h}"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/AudioSides.xcarchive"
APP="$OUT/export/AudioSides.app"

rm -rf "$OUT"
mkdir -p "$OUT"

# Keep account-specific export settings in ignored build output.
cp "$ROOT/scripts/ExportOptions.plist" "$OUT/ExportOptions.plist"
plutil -insert teamID -string "$TEAM_ID" "$OUT/ExportOptions.plist"
plutil -insert signingCertificate -string "$IDENTITY" "$OUT/ExportOptions.plist"

echo "› Archiving"
xcodebuild archive \
  -project "$ROOT/AudioSides.xcodeproj" \
  -scheme AudioSides \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet

echo "› Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  -quiet

echo "› Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow \
  && { echo "Release build has the get-task-allow entitlement; notarization would fail."; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$OUT/AudioSides-$VERSION.zip"
DMG="$OUT/AudioSides-$VERSION.dmg"

# Submits a file to Apple's notary service and stops unless it's accepted.
notarize() {
  local result
  result=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1) || true
  print -r -- "$result"
  if ! grep -q "status: Accepted" <<< "$result"; then
    echo "Notarization of ${1:t} wasn't accepted. For details, run:"
    echo "  xcrun notarytool log <submission id above> --keychain-profile $PROFILE"
    exit 1
  fi
}

echo "› Notarizing the app (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
notarize "$OUT/notarize.zip"
rm "$OUT/notarize.zip"

echo "› Stapling the app"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

# A disk image with the stapled app and an Applications shortcut to drag it onto.
echo "› Building the disk image"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/AudioSides.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AudioSides" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "› Notarizing the disk image"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "✓ $DMG"
echo "✓ $ZIP"
