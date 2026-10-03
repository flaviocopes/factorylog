#!/bin/zsh
# Builds the universal release app, signs with Developer ID when the certificate
# is in the keychain (ad hoc on CI and forks), notarizes when signed that way,
# and writes dist/Factory-Log-<version>.zip for a GitHub release. The zip holds
# Factory Log.app at its top, which is what the in-app updater expects.
# dist/Factory Log.app stays next to it: the Releases app takes the project's
# name and icon from it.
# Usage: zsh Scripts/build-release.zsh

set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/FactoryLog-Info.plist)
BUILT_APP="$ROOT/.build/Factory Log.app"
APP="$ROOT/dist/Factory Log.app"
ZIP="$ROOT/dist/Factory-Log-$VERSION.zip"
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT

mkdir -p dist
rm -rf "$ZIP" "$APP"
FACTORYLOG_UNIVERSAL=1 zsh Scripts/build-app.zsh release >/dev/null
ditto "$BUILT_APP" "$APP"

lipo "$APP/Contents/MacOS/FactoryLog" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/factorylog" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [[ "$TEAM" == DGFKNTAG99 ]]; then
  SIGNATURE_LABEL="Developer ID"
else
  SIGNATURE_LABEL="ad-hoc"
fi
print "Release signature: $SIGNATURE_LABEL (TeamIdentifier=${TEAM:-none})"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ "$TEAM" == DGFKNTAG99 ]]; then
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  if [[ $(plutil -extract status raw -o - - <<< "$result") != Accepted ]]; then
    print -u2 "$result"
    xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$result")" --keychain-profile notary >&2
    exit 1
  fi

  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Factory Log.app"

print "$ZIP"
shasum -a 256 "$ZIP"
