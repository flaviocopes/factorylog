# Changelog

Factory Log follows semantic versioning.

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
