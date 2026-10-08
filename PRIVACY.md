# Privacy

Work Tracebook has no accounts, analytics, advertising, or hosted service. It doesn't read source code, Git history, diffs, or terminal output.

Agent-written task events are stored locally in the event file, `~/Library/Application Support/Factory Log/events.jsonl` by default. The app watches that file and keeps two more beside it: `narratives.json` for day recaps and, after a confirmed purge, `daily-aggregates.json` for activity totals. Installing the CLI or an agent integration changes only the local files named on the setup screen, and only after you press the button.

The app goes online in two cases:

- **Update checks.** Once a day it asks the GitHub API for the latest release of `flaviocopes/work-tracebook`, sending only the app's name and version as the user agent. It downloads a release only when you choose **Install and Relaunch**. Turn the daily check off with `defaults write dev.factorylog.app AppUpdaterAutomaticChecks -bool false`.
- **Day recaps.** When an Ollama-compatible endpoint answers, finished days' project names, task titles and summaries are sent to it to write one sentence per project. The default endpoint is on your Mac. Changing `FACTORYLOG_OLLAMA_HOST` to another machine sends that text there, so trust that machine first.

The optional `Scripts/import-git-history.py` importer runs only when you start it. It reads commit subjects, dates, and author emails from local repositories. When `cursor-agent` is installed, it sends those subjects to Cursor to write task titles. Pass `--no-titles` to keep the import local.

Work Tracebook doesn't upload logs, event history, crash reports, or configuration.
