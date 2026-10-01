#!/bin/zsh
# Builds the universal, ad-hoc signed app, checks the signature survives zipping,
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
FACTORYLOG_SIGN_IDENTITY=- FACTORYLOG_UNIVERSAL=1 zsh Scripts/build-app.zsh release >/dev/null
ditto "$BUILT_APP" "$APP"

lipo "$APP/Contents/MacOS/FactoryLog" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/factorylog" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Factory Log.app"

print "$ZIP"
shasum -a 256 "$ZIP"
