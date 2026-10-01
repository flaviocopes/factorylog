# Architecture

Factory Log is a local-first macOS app with three Swift Package Manager targets.

## Targets

- `FactoryLogCore` owns the event model, JSON contract, transactional event
  store, history queries, active-time estimate, file watcher, and optional
  narrative engine. Active time is derived from update timestamps: updates in
  a project at most 45 minutes apart form one session, plus 5 minutes of
  lead-in per session. Nothing about time is stored.
- `factorylog` parses agent commands, validates input, and writes events through
  the core transaction API.
- `FactoryLogApp` watches the store and derives four views: Today and
  Yesterday (a day timeline plus every task), Week (a seven-day ribbon of
  sessions, the project split, and shipped outcomes), and Insights (long-range
  time and activity). It also provides explicit setup actions for the bundled
  CLI and agent templates.

## Data flow

1. An agent invokes `factorylog start`, `report`, or `archive`.
2. The CLI reads the current task state and constructs a versioned event.
3. `EventStore.appendValidated(_:)` takes an interprocess lock, reloads and
   validates state, then performs one append-mode write and synchronizes it.
4. The app's vnode watcher observes the append and reloads a snapshot.
5. On reload, the app archives open tasks that started at least 24 hours ago.
   This scan and its appends run under one exclusive store lock.
6. Valid records remain visible even if another line is malformed or belongs to
   a future schema; the UI reports ignored line numbers.
7. Past-day project reports may be sent to a configured Ollama-compatible host.
   The resulting sentence is cached beside the event log.
8. An explicit settings action can compact old detail under the same exclusive
   lock while preserving essential task events and merging removed activity into
   daily project aggregates.

## Storage

The primary store is newline-delimited JSON at:

```text
~/Library/Application Support/Factory Log/events.jsonl
```

Each record is self-contained. A sibling lock file coordinates Factory Log
writers. The narrative cache is `narratives.json`. Neither file is synced or
uploaded by Factory Log.

Confirmed history compaction rewrites the detailed event file atomically and
stores preserved counts in `daily-aggregates.json`. It never runs automatically,
requires at least 30 days of detailed retention, keeps every event for open
tasks, and keeps the start and final outcome for completed tasks.

## Concurrency and recovery

All user-facing mutations are serialized across processes. The validation and
append happen under the same lock, preventing duplicate starts, updates after
archive, and writers overwriting the same file offset. Readers use a shared
lock, ignore an incomplete final line, and return record-level issues for
malformed or unsupported complete records.

## App distribution

`Scripts/build-app.zsh` assembles the SwiftPM executables, asset catalog,
integration templates, plist, and signatures into a standard app bundle. The
CLI lives under `Contents/Helpers`. `Scripts/build-release.zsh` builds the
universal, ad hoc signed app and zips it for GitHub Releases.

`AppUpdater` checks the latest GitHub release once a day. To install one, it
downloads the zip beside the app, compares its SHA-256 with GitHub's digest,
checks the bundle identifier, version, and code signature, replaces the app in
place without the quarantine flag, and relaunches it. [DISTRIBUTION.md](DISTRIBUTION.md)
lists the release contract that keeps this working.
