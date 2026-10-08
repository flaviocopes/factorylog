#!/bin/zsh
# Captures the README screenshots from a generated demo log, in light and dark.
# A debug build draws its own window on request (DebugSnapshot.swift), so this
# needs no Screen Recording permission. It quits Work Tracebook while it runs.
# Usage: zsh Scripts/screenshots.zsh

set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"
OUT="$ROOT/docs"
DEMO=$(mktemp -d)
trap 'rm -rf "$DEMO"' EXIT

python3 Scripts/make-demo-log.py "$DEMO/events.jsonl" >/dev/null
mkdir -p "$DEMO/empty" "$OUT"
zsh Scripts/build-app.zsh debug >/dev/null

quit_app() {
  osascript -e 'quit app "Work Tracebook"' 2>/dev/null || true
  sleep 1
  pkill -f 'MacOS/Work Tracebook' 2>/dev/null || true
  sleep 1
}

# Launches against a store, in an appearance, at the default window size, in English.
launch() {
  quit_app
  open -n --env FACTORYLOG_EVENTS_FILE="$1" ".build/Work Tracebook.app" --args \
    -appearance "$2" -projectTimeRange 30 -ApplePersistenceIgnoreState YES -DebugActiveWindow YES \
    -AppleLanguages '(en)' -AppleLocale en_US
  sleep 8
}

snap() {
  rm -f "$2"
  swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"dev.factorylog.debug.snapshot\"), object: \"$1|$2\", userInfo: nil, deliverImmediately: true)" 2>/dev/null
  for _ in {1..80}; do
    [[ -f "$2" ]] && break
    sleep 0.25
  done
  [[ -f "$2" ]] || { print -u2 "No snapshot for $1"; exit 1 }
  swift Scripts/frame-screenshot.swift "$2"
  print "$2"
}

for appearance in light dark; do
  launch "$DEMO/events.jsonl" "$appearance"
  snap today "$OUT/screenshot-today-$appearance.png"
  snap week "$OUT/screenshot-week-$appearance.png"
  snap "insights@$HOME/Projects/storefront" "$OUT/screenshot-insights-$appearance.png"
done

launch "$DEMO/empty/events.jsonl" light
snap today "$OUT/screenshot-welcome-light.png"
quit_app
