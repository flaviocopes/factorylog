#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
APP_PATH="$ROOT/.build/Work Tracebook.app"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Work Tracebook"
CLI_EXECUTABLE="$APP_PATH/Contents/Helpers/factorylog"
cd "$ROOT"
EXPECTED_VERSION=$(sed -n 's/^ *public static let current = "\(.*\)"$/\1/p' Sources/FactoryLogCore/FactoryLogVersion.swift)

swift test
python3 -m py_compile Scripts/import-codex-work-log.py Scripts/import-git-history.py Scripts/benchmark-event-store.py
zsh Scripts/build-app.zsh release

plutil -lint "$PLIST_PATH"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")
CLI_VERSION=$($CLI_EXECUTABLE --version | awk '{print $2}')
if [[ "$APP_VERSION" != "$EXPECTED_VERSION" || "$CLI_VERSION" != "$EXPECTED_VERSION" ]]; then
  print -u2 "Expected version $EXPECTED_VERSION; app=$APP_VERSION cli=$CLI_VERSION"
  exit 1
fi

for REQUIRED in \
  "$CLI_EXECUTABLE" \
  "$APP_PATH/Contents/Resources/Integrations/agent-instructions.md" \
  "$APP_PATH/Contents/Resources/Integrations/cursor-factory-log.mdc"; do
  if [[ ! -f "$REQUIRED" ]]; then
    print -u2 "Missing release file: $REQUIRED"
    exit 1
  fi
done

ARCHITECTURES=(${(s: :)$(lipo -archs "$APP_EXECUTABLE")})
if (( ${ARCHITECTURES[(I)arm64]} == 0 || ${ARCHITECTURES[(I)x86_64]} == 0 )); then
  print -u2 "Release app is not universal: ${ARCHITECTURES[*]}"
  exit 1
fi
CLI_ARCHITECTURES=(${(s: :)$(lipo -archs "$CLI_EXECUTABLE")})
if (( ${CLI_ARCHITECTURES[(I)arm64]} == 0 || ${CLI_ARCHITECTURES[(I)x86_64]} == 0 )); then
  print -u2 "Release CLI is not universal: ${CLI_ARCHITECTURES[*]}"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO=$(codesign -dvv "$APP_PATH" 2>&1)
if [[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]; then
  :
elif [[ "$SIGNATURE_INFO" == *"TeamIdentifier=DGFKNTAG99"* && "$SIGNATURE_INFO" == *"flags=0x10000"* ]]; then
  :
else
  print -u2 "Expected an ad hoc signature or Developer ID (team DGFKNTAG99) with hardened runtime."
  exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
STORE="$TEMP_DIR/events.jsonl"
"$CLI_EXECUTABLE" start \
  --task-id release-stress \
  --title "Release stress" \
  --summary "Started" \
  --project-path "$TEMP_DIR" \
  --store "$STORE" >/dev/null

for INDEX in {1..200}; do
  "$CLI_EXECUTABLE" report \
    --task-id release-stress \
    --summary "Report $INDEX" \
    --store "$STORE" \
    >"$TEMP_DIR/out-$INDEX" \
    2>"$TEMP_DIR/error-$INDEX" &
done
wait

LINE_COUNT=$(wc -l < "$STORE" | tr -d ' ')
ERROR_COUNT=$(find "$TEMP_DIR" -name 'error-*' -type f -size +0c | wc -l | tr -d ' ')
if [[ "$LINE_COUNT" != "201" || "$ERROR_COUNT" != "0" ]]; then
  print -u2 "Concurrent write verification failed: lines=$LINE_COUNT errors=$ERROR_COUNT"
  exit 1
fi

# Whoever builds the release must not leak their own home folder into public files.
if git ls-files -z | xargs -0 grep -I -n -F "$HOME/" -- 2>/dev/null; then
  print -u2 "Tracked files mention this machine's home folder."
  exit 1
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi
python3 Scripts/benchmark-event-store.py --cli "$CLI_EXECUTABLE" --events 10000 --reports 3

print "Work Tracebook $EXPECTED_VERSION release verification passed."
