#!/bin/bash
# Build, sign, notarize and package a release into build/release/:
# Kitfold-<version>.dmg (universal app, Developer ID, notarized and stapled) and SHA256SUMS.
#   NOTARY_PROFILE=<notarytool keychain profile> scripts/release.sh
# Without NOTARY_PROFILE everything is signed but not notarized; don't publish that.
# SIGN_IDENTITY picks another Developer ID Application certificate. See docs/development.md.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Xingyi Liao (HMDAVG9B8J)}"
OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"

notarize() {  # <file>: submit, wait, and stop unless Apple accepted it
  local result status
  result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
  status=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$result")
  if [ "$status" != "Accepted" ]; then
    echo "$result" >&2
    echo "Notarization: $status. Details: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi
}

echo "▸ Build (arm64 + x86_64)"
ARCHS="arm64 x86_64" scripts/bundle.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Kitfold.app/Contents/Info.plist)
APP="$OUT/Kitfold.app"
ditto build/Kitfold.app "$APP"

echo "▸ Sign Kitfold $VERSION"
# The bundled CLI first, then the app: Developer ID, hardened runtime, secure timestamp.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/kitfold"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarize the app"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  notarize "$OUT/notarize.zip"
  rm "$OUT/notarize.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "▸ Disk image"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Kitfold.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Kitfold-$VERSION.dmg"
hdiutil create -volname "Kitfold $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarize the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi
# Installs come from the disk image: leave no loose copy of the signed app behind.
rm -rf "$STAGE" "$APP"

(cd "$OUT" && shasum -a 256 "Kitfold-$VERSION.dmg" >SHA256SUMS)
echo "Built $DMG"
[ -n "${NOTARY_PROFILE:-}" ] || echo "Not notarized (no NOTARY_PROFILE): don't publish this one." >&2
