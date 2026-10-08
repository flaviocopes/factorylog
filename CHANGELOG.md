# Changelog

Work Tracebook follows semantic versioning.

## 1.3.0 (October 8, 2026)

- Renamed the app to Work Tracebook.
- Updated its GitHub repository, app bundle and download names. Existing saved data and commands still work.

## 1.2.0 — 2026-10-03

- **Signed and notarized.** Work Tracebook is now signed with my Apple Developer ID and notarized by Apple. The first time you open it, macOS no longer says it "could not verify Work Tracebook is free of malware", so you don't need **Open Anyway** or Terminal. It asks the usual question about opening an app downloaded from the internet, and you click **Open**.
- Nothing else changed. Your event log, the `factorylog` CLI and the agent instructions stay the same.

## 1.1.0 — 2026-10-01

- Setup checks that your login shell can find `factorylog`, since agents get their `PATH` from it. On zsh, **Add to PATH** fixes it in `~/.zshenv`.
- **Connect Codex** also adds the log folder to Codex's sandbox in `~/.codex/config.toml`, so Codex can write its reports.
- **Send a test report** checks the command and the log without waiting for an agent.
- The README explains how agents reach the app, where other agents keep their instructions, and what to check when reports don't show up.

## 1.0.0 — 2026-10-01

The first public release.

- Today and Yesterday show what you did: active time, projects, tasks, and a timeline with one lane per project and a bar per work session.
- Each task appears once with its latest report. Open tasks can be closed with a final outcome, and tasks open for 24 hours are marked Done automatically.
- Finished days get a one-sentence recap per project from an optional local Ollama model, cached and refreshed when the day changes.
- The Week view shows seven days of sessions, where the time went, and what shipped, and steps back through earlier weeks.
- Insights shows time by project over 7, 30, or 90 days or all time, a 26-week heatmap, and a panel with every task in a project.
- Active time is estimated from when reports arrive, in sessions of updates at most 45 minutes apart.
- A welcome screen installs the CLI and connects Codex or Cursor. Empty screens preview what they will show.
- Projects can be hidden, and work inside agent folders such as `~/.cursor` never shows.
- ⌘1 to ⌘4 switch screens, and the arrow keys and Esc move around a day or a week.
- The app updates itself from GitHub Releases after verifying the download.
- The `factorylog` CLI records starts, reports, and archives in an append-only JSONL log, safely across concurrent agents.
- Settings can purge old detail on request while keeping daily totals and essential task history.
