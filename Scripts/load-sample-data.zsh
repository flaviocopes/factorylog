#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
CLI=${FACTORYLOG_CLI:-"$ROOT/.build/debug/factorylog"}
STORE=${FACTORYLOG_STORE:-"$HOME/Library/Application Support/Factory Log/events.jsonl"}
SUFFIX="$(date +%s)_$$"
DOING_ID="sample_doing_$SUFFIX"
DONE_ID="sample_done_$SUFFIX"

if [[ ! -x "$CLI" ]]; then
  print -u2 "Build Work Tracebook first with: swift build"
  exit 1
fi

"$CLI" start \
  --task-id "$DOING_ID" \
  --project-name "Work Tracebook Sample" \
  --project-path "$ROOT" \
  --title "Improve the activity timeline" \
  --summary "Started refining the daily activity timeline." \
  --source cursor \
  --store "$STORE"

"$CLI" report \
  --task-id "$DOING_ID" \
  --summary "Added clearer timestamps and project labels." \
  --store "$STORE"

"$CLI" start \
  --task-id "$DONE_ID" \
  --project-name "Work Tracebook Sample" \
  --project-path "$ROOT" \
  --title "Verify local event storage" \
  --summary "Started checking append-only event storage." \
  --source codex \
  --store "$STORE"

"$CLI" report \
  --task-id "$DONE_ID" \
  --summary "Verified that events survive an app restart." \
  --store "$STORE"

"$CLI" archive \
  --task-id "$DONE_ID" \
  --summary "Finished storage verification." \
  --store "$STORE"

print
print "Added sample data to $STORE"
