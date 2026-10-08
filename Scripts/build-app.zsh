#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
CONFIGURATION=${1:-debug}

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  print -u2 "Usage: zsh Scripts/build-app.zsh [debug|release]"
  exit 2
fi

if [[ -n ${FACTORYLOG_SIGN_IDENTITY+x} ]]; then
  SIGN_IDENTITY=$FACTORYLOG_SIGN_IDENTITY
else
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
  SIGN_IDENTITY=${SIGN_IDENTITY:--}
fi

BUILD_ARGS=(--package-path "$ROOT" --configuration "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" && "${FACTORYLOG_UNIVERSAL:-1}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGS[@]}" --product FactoryLogApp
swift build "${BUILD_ARGS[@]}" --product factorylog

BIN_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

APP_PATH="$ROOT/.build/Work Tracebook.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
HELPERS_PATH="$CONTENTS_PATH/Helpers"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH" "$HELPERS_PATH"
rm -f "$CONTENTS_PATH/AppIcon-Info.plist"
cp "$BIN_PATH/FactoryLogApp" "$MACOS_PATH/Work Tracebook"
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
chmod +x "$MACOS_PATH/Work Tracebook"
chmod +x "$HELPERS_PATH/factorylog"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  signature_label="Developer ID"
  typeset -a mach_o_paths
  while IFS= read -r mach_path; do
    [[ -n "$mach_path" ]] && mach_o_paths+=("$mach_path")
  done < <(
    find "$APP_PATH" -type f -print0 | xargs -0 file 2>/dev/null |
      sed -n 's/: .*Mach-O.*//p' |
      awk '{ depth = gsub(/\//, "/"); print depth, $0 }' |
      sort -k1,1nr -k2,2 |
      cut -d' ' -f2-
  )
  for mach_path in "${mach_o_paths[@]}"; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$mach_path"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  signature_label="ad-hoc"
  codesign --force --sign - "$HELPERS_PATH/factorylog"
  codesign --force --sign - "$APP_PATH"
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_PATH/Info.plist")
CLI_VERSION=$($HELPERS_PATH/factorylog --version | awk '{print $2}')
if [[ "$APP_VERSION" != "$CLI_VERSION" ]]; then
  print -u2 "App version $APP_VERSION does not match CLI version $CLI_VERSION."
  exit 1
fi

print "$APP_PATH ($signature_label signed)"
