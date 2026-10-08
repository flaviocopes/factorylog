# Work Tracebook

Work Tracebook is a native macOS app, a companion CLI, and a shared core library in one Swift 6.2 package. Coding agents report finished work through the CLI, and the app turns those reports into a timeline of each day and week. The event log stays local, append-only, and readable without the app.

This file is public. Keep notes about your own machine in `.cursor/rules/*.local.mdc`, which git ignores.

## Files

- `Sources/FactoryLogCore/`: the event model and JSON contract, `EventStore` (locked appends, validation, compaction), `FactoryLogHistory` (tasks, days, projects), `FactoryLogActiveTime` (work sessions and estimated time), `EventStoreWatcher`, and `DayNarrator` (optional one-sentence recaps from a local Ollama model).
- `Sources/FactoryLogCLI/`: the `factorylog` command agents call. The agent-ready manifest lives in `FactoryLogCapabilities.swift`; every version bump adds a changelog entry there.
- `Sources/FactoryLogApp/`: the SwiftUI app.
  - `FactoryLogApp.swift`: the window, the Today, Yesterday, Week and Insights screens, reloading, and the update menu item.
  - `DayView.swift`, `DaySummaryView.swift`: one day, with its timeline, summary and log.
  - `WeekView.swift`, `TimelineCharts.swift`: the week ribbon, the day timeline and the project donut.
  - `ActivityDashboardView.swift`, `PortfolioDashboardView.swift`, `ProjectTime.swift`, `ProjectDetailPanel.swift`, `DashboardData.swift`, `DashboardSharedViews.swift`: Insights and the project panel.
  - `WelcomeView.swift`: the first-run setup and the empty-screen previews.
  - `AgentSetup.swift`: installing the CLI and agent instructions, the login-shell PATH check, Codex sandbox access and the test report.
  - `AppSettingsView.swift`, `HiddenProjects.swift`, `ProjectPalette.swift`: settings, hidden projects, project colors.
  - `AppUpdater.swift`: in-app updates from GitHub Releases, a copy of a shared template.
  - `DebugSnapshot.swift`: debug builds only, draws the window to a PNG on request.
- `Integrations/`: the agent instructions and Cursor rule the app installs.
- `Scripts/`: building, releasing, verification, screenshots and importers.
- `docs/`: the event contract and the agent integration guides.

## Build and run

Requires macOS 15 and Swift 6.2 (Xcode 26).

```sh
swift test                               # core and CLI tests
zsh Scripts/build-app.zsh debug          # .build/Work Tracebook.app
open ".build/Work Tracebook.app"
zsh Scripts/verify-release.zsh           # tests, universal release build, signatures, concurrent writes
zsh Scripts/build-release.zsh            # dist/Work-Tracebook-<version>.zip; notarizes when Developer ID signed
zsh Scripts/screenshots.zsh              # docs/ screenshots from a generated demo log
```

## Rules

- Read `ARCHITECTURE.md` and `docs/event-contract.md` before changing storage. Keep schema version 1 readable unless the change ships a documented migration and fixtures.
- Shared storage and model behavior goes in `FactoryLogCore`. The CLI and the app are clients of it.
- Never collect source code, diffs, terminal output, or secrets.
- User-facing mutations go through `EventStore.appendValidated(_:)`. Don't bypass its cross-process transaction.
- Concurrency changes need a multi-writer regression test.
- `Sources/FactoryLogApp/AppUpdater.swift` is a copy of a template shared by several apps. Don't edit it here.
- Releases are signed with Flavio's Developer ID (team `DGFKNTAG99`) with the hardened runtime, and notarized by `Scripts/build-release.zsh`. It needs the certificate in the keychain and a notarytool keychain profile named `notary`. CI and forks have no certificate, so `Scripts/build-app.zsh` signs ad-hoc there. The release contract, or installed copies can't update: the tag is `vX.Y.Z`, equal to `CFBundleShortVersionString` in `Resources/FactoryLog-Info.plist` and `FactoryLogVersion.current`. The release is the latest one, not a draft or prerelease, with one universal zip made by `Scripts/build-release.zsh`, `Work Tracebook.app` at its top. The notes start with what's new, since the update dialog shows them up to `## Install`.
- Screenshots and videos use generated demo data, never a real event log.
- After changing anything under `Sources/`, rebuild and relaunch the app bundle (`.cursor/rules/restart-app-after-change.mdc`).

## Learned User Preferences

- Keep the UI minimal: list each task once (never one row per status) and drop redundant chrome such as Done checkmarks, "Thread history", update counts, and "X daily work" headings.
- Order log entries newest first, show relative times ("5 minutes ago"), and hide repeated identical time labels rather than regrouping rows.
- Lists must update live from the event store; never rely on a manual refresh button.
- Summaries describe one person plus agents, never "the team": write "Implemented X, Y, Z" in plain past tense.
- On past days the Summary tab shows only project name, time, and one sentence per project; the Log tab shows every individual update.
- Keyboard: ⌘1 to ⌘4 switch screens; Left/Right arrows switch between Summary and Log on a day and between weeks on Week; Esc leaves a project filter, then a day opened from another screen.
- Videos and showreels use a light background and keep sound effects, with no background music or noise.

## Learned Workspace Facts

- The app executable product is `FactoryLogApp`, not `FactoryLog`: on the case-insensitive macOS filesystem `FactoryLog` collides with the `factorylog` CLI in `.build/debug`, and running the CLI launched the GUI.
- Day summaries use a local Ollama model (`gemma3:4b` by default; override with `FACTORYLOG_OLLAMA_MODEL` and `FACTORYLOG_OLLAMA_HOST`) cached in `narratives.json`, keyed by the day's start formatted in UTC. No cloud AI. Counts and task titles stay computed from events and are the fallback when no sentence exists.
- Active time is estimated, not tracked: updates in a project at most 45 minutes apart form a session, plus 5 minutes of lead-in. Automatic archives count for nothing and don't make a task active on a day.
- Work done inside an agent's own folder (`~/.cursor`, `~/.codex`, `~/.claude`, `~/.agents`) never shows in the app.
- `Scripts/import-git-history.py` backfills gaps from local Git commits: one task per 45-minute commit session, skipping commits existing tasks already cover. Re-runs are safe because task IDs are deterministic. It sends commit subjects to `cursor-agent` for titles unless you pass `--no-titles`.
- Agents run the `factorylog` copy in `~/.local/bin`, which only Install or Reinstall CLI and `Scripts/install-cli.zsh` write. App updates don't refresh it, so it can be older than the source. Reinstall it before testing CLI changes through an agent.
- `docs/rfcs/` holds the draft DARP RFC and schema. Work Tracebook follows DARP's ideas, but its schema version 1 records aren't DARP 1.0 records and no adapter exists, so don't call its output DARP.
- `Scripts/verify-release.zsh` fails if any tracked file contains the builder's home folder path, so tracked files use `~` or repo-relative paths.
- `screencapture` doesn't work from an agent shell without Screen Recording permission. Debug builds draw their own window on a distributed notification instead; see `.cursor/rules/restart-app-after-change.mdc`.

## Naming compatibility

The public app name is Work Tracebook. Keep its existing bundle ID, saved data paths, URL schemes, CLI commands and internal Swift targets so installed copies and agent integrations remain compatible. Use the renamed checkout folder and GitHub repository in new links and build instructions.
