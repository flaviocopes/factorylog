# Factory Log event contract

Factory Log stores one JSON object per line in an append-only event file. Every event is self-contained so the history remains readable even if an agent task is later archived or its source tool is unavailable.

```json
{
  "schemaVersion": 1,
  "id": "01J...",
  "taskID": "task_...",
  "timestamp": "2026-07-26T09:41:00Z",
  "kind": "task.reported",
  "project": {
    "name": "Factory Log",
    "path": "/Users/example/Projects/factory-log"
  },
  "taskTitle": "Build the Factory Log prototype",
  "source": {
    "tool": "codex",
    "sessionID": "019f..."
  },
  "summary": "Built the first native chronicle and connected it to the local event store."
}
```

Required fields:

- `schemaVersion`: currently `1`.
- `id`: unique event identifier.
- `taskID`: stable identifier shared by every event in one agent task.
- `timestamp`: RFC 3339 timestamp with an explicit time zone.
- `kind`: `task.started`, `task.reported`, or `task.archived`.
- `project.name`: human-readable project name.
- `project.path`: absolute local project path.
- `taskTitle`: human-readable title copied onto every event.
- `source.tool`: agent application, initially `codex`, `cursor`, or `other`.
- `summary`: the agent's plain-language report.

`source.sessionID` is optional because not every agent tool exposes a stable session identifier. When `source.tool` is `codex`, the CLI records `CODEX_THREAD_ID` automatically if it is available. Source identifiers are open strings so new agent tools remain readable without a schema change.

A task is **Doing** after its first `task.started` event. It becomes **Done** when its first `task.archived` event appears. The app automatically appends an archive event when a task has been open for 24 hours. This also happens when the app next opens or becomes active if the deadline passed while it was closed. Factory Log never infers priority, next actions, progress percentages, or completion from prose. Events are never edited or deleted; corrections are additional `task.reported` events.

The default store is `~/Library/Application Support/Factory Log/events.jsonl`. Factory Log writers serialize validation and append operations through an interprocess lock and write one complete newline-terminated JSON object at a time. Readers ignore an incomplete final line. Malformed complete records and unsupported schema versions are reported by line number while readable records remain available; mutations stop until those issues are repaired.

## Command-line logger

Agents write events with explicit flags. `start` defaults the project path to the current directory and generates a task ID when one is not supplied.

```sh
factorylog start \
  --title "Build the Factory Log prototype" \
  --summary "Started the command-line logger." \
  --source cursor

factorylog report \
  --task-id task_123 \
  --summary "Added append-only event storage."

factorylog archive \
  --task-id task_123 \
  --summary "Finished and verified the logger."
```

Successful commands write a JSON object containing the event and store path to standard output. Validation failures write a JSON error to standard error and exit with status `2`.

All commands accept an optional RFC 3339 `--timestamp` value. Normal agent logging omits it and uses the current time. Historical importers use it to preserve the original date and time.
