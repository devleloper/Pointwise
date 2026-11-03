#!/usr/bin/env bash
# Builds a Release Pointwise.app and packages it as build/Pointwise-<version>.zip and .dmg.
#
# Signing, from the environment:
#   DEVELOPER_ID_IDENTITY  "Developer ID Application: Name (TEAMID)" — signs for distribution.
#                          Without it the app is ad-hoc signed (fine for local testing).
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                          App Store Connect API key — notarizes and staples both packages.
#   REQUIRE_NOTARIZATION=1 Fail instead of silently skipping notarization (used by CI).
# See docs/RELEASING.md.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED_DATA="build/DerivedData"
IDENTITY="${DEVELOPER_ID_IDENTITY:--}"

xcodebuild \
  -project Pointwise.xcodeproj \
  -scheme Pointwise \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

APP="$DERIVED_DATA/Build/Products/Release/Pointwise.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="build/Pointwise-$VERSION.zip"
DMG="build/Pointwise-$VERSION.dmg"

# Re-sign with the hardened runtime and a secure timestamp; ad-hoc signatures cannot have one.
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --options runtime --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

# Fails unless Apple accepted the submission; the exit status of `--wait` alone isn't relied on.
notarize() {
  local result status
  result=$(xcrun notarytool submit "$1" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --timeout 30m --output-format json) || true
  status=$(echo "$result" | plutil -extract status raw -o - - 2>/dev/null) || status="no result"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization of $1 failed: $status" >&2
    echo "$result" >&2
    echo "Details: xcrun notarytool log $(echo "$result" | plutil -extract id raw -o - -) --key … --key-id … --issuer …" >&2
    exit 1
  fi
}

CAN_NOTARIZE=false
if [[ "$IDENTITY" != "-" && -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  CAN_NOTARIZE=true
fi
if [[ "${REQUIRE_NOTARIZATION:-0}" == 1 && $CAN_NOTARIZE != true ]]; then
  echo "Notarization is required, but DEVELOPER_ID_IDENTITY or NOTARY_* is missing" >&2
  exit 1
fi

if $CAN_NOTARIZE; then
  ditto -c -k --keepParent "$APP" "build/notarize.zip"
  notarize "build/notarize.zip"
  rm -f "build/notarize.zip"
  xcrun stapler staple "$APP"
fi

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Pointwise.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Pointwise" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if $CAN_NOTARIZE; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

(cd build && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "Pointwise-$VERSION.sha256")

if $CAN_NOTARIZE; then
  echo "Packaged $ZIP and $DMG (Developer ID, notarized)"
elif [[ "$IDENTITY" != "-" ]]; then
  echo "Packaged $ZIP and $DMG (Developer ID, NOT notarized)"
else
  echo "Packaged $ZIP and $DMG (ad-hoc signed, for local testing only)"
fi
