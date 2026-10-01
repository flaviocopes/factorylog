#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
CONFIGURATION=${1:-debug}
SIGN_IDENTITY=${FACTORYLOG_SIGN_IDENTITY:--}

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  print -u2 "Usage: zsh Scripts/build-app.zsh [debug|release]"
  exit 2
fi

BUILD_ARGS=(--package-path "$ROOT" --configuration "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" && "${FACTORYLOG_UNIVERSAL:-1}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGS[@]}" --product FactoryLogApp
swift build "${BUILD_ARGS[@]}" --product factorylog

BIN_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

APP_PATH="$ROOT/.build/Factory Log.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
HELPERS_PATH="$CONTENTS_PATH/Helpers"

mkdir -p "$MACOS_PATH" "$RESOURCES_PATH" "$HELPERS_PATH"
rm -f "$CONTENTS_PATH/AppIcon-Info.plist"
cp "$BIN_PATH/FactoryLogApp" "$MACOS_PATH/FactoryLog"
cp "$BIN_PATH/factorylog" "$HELPERS_PATH/factorylog"
cp "$ROOT/Resources/FactoryLog-Info.plist" "$CONTENTS_PATH/Info.plist"
rm -rf "$RESOURCES_PATH/Integrations"
cp -R "$ROOT/Integrations" "$RESOURCES_PATH/Integrations"
xcrun actool "$ROOT/Resources/Assets.xcassets" \
  --compile "$RESOURCES_PATH" \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ROOT/.build/AppIcon-Info.plist"
chmod +x "$MACOS_PATH/FactoryLog"
chmod +x "$HELPERS_PATH/factorylog"

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "$HELPERS_PATH/factorylog"
codesign "${SIGN_ARGS[@]}" "$APP_PATH"

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_PATH/Info.plist")
CLI_VERSION=$($HELPERS_PATH/factorylog --version | awk '{print $2}')
if [[ "$APP_VERSION" != "$CLI_VERSION" ]]; then
  print -u2 "App version $APP_VERSION does not match CLI version $CLI_VERSION."
  exit 1
fi

print "$APP_PATH"
