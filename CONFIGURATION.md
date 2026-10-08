# Configuration

Work Tracebook works with no configuration after its CLI and one agent instruction
set are installed.

## Files

| Purpose | Default path |
|---|---|
| Event history | `~/Library/Application Support/Factory Log/events.jsonl` |
| Writer lock | `~/Library/Application Support/Factory Log/events.jsonl.lock` |
| Compacted daily totals | `~/Library/Application Support/Factory Log/daily-aggregates.json` |
| Narrative cache | `~/Library/Application Support/Factory Log/narratives.json` |
| User CLI | `~/.local/bin/factorylog` |
| PATH line for zsh | `~/.zshenv` |
| Codex instructions | `~/.codex/AGENTS.md` |
| Codex sandbox access | `~/.codex/config.toml` |
| Cursor rule | `~/.cursor/rules/factory-log.mdc` |

The welcome screen and Settings install the bundled CLI and only change agent files
after the user presses the corresponding button. **Add to PATH** appears only when
the login shell is zsh and can't find `factorylog`, and appends one `export` line
to `~/.zshenv`. **Connect Codex** appends a `[sandbox_workspace_write]` section
with the log folder in `writable_roots` to `~/.codex/config.toml`, unless the file
already mentions the folder, uses `danger-full-access`, or has a sandbox section of
its own, which the app never edits. Both append in place, so a dotfile that is a
symlink stays one.

Whether `factorylog` is on the PATH comes from running `command -v factorylog` in
the user's login shell, because that shell, not the app, sets the PATH agents see.
**Send a test report** runs `factorylog start` and `factorylog archive` the same
way, for a closed task called "Test report" in a project named Work Tracebook.

The detailed-history setting controls only the preview and explicit purge
action. Work Tracebook never compacts history on a timer or at launch.

## Environment variables

- `FACTORYLOG_EVENTS_FILE` points the app, watcher, and CLI default at another
  JSONL event store. Use an absolute path for predictable agent behavior.
- `FACTORYLOG_OLLAMA_MODEL` selects the Ollama model; default `gemma3:4b`.
- `FACTORYLOG_OLLAMA_HOST` selects the Ollama-compatible base URL; default
  `http://127.0.0.1:11434`.
- `FACTORYLOG_INSTALL_DIR` changes the destination used by `install-cli.zsh`.
- `FACTORYLOG_CLI` and `FACTORYLOG_STORE` customize sample-data loading.

The CLI also accepts `--store` per command, which takes precedence over the
environment default. Agents writing one shared history must use the same store path.

## App preferences

The app keeps its preferences in the `dev.factorylog.app` defaults domain. Most
are set from Settings or the screens themselves: the appearance, hidden
projects, the detailed-history retention, and the Insights time range. The
update check has three keys of its own:

| Key | What it does |
|---|---|
| `AppUpdaterAutomaticChecks` | `false` turns off the daily check. **Check for Updates…** still works |
| `AppUpdaterLastCheck` | When the last automatic check ran |
| `AppUpdaterSkippedVersion` | The version picked with **Skip This Version** |

## Legacy text-log import

The importer defaults to the system time zone and common project roots. Use
`--timezone`, repeatable `--project-root`, and repeatable
`--project-map NAME=/absolute/path` options when importing another layout. It
refuses to invent a path for a project it cannot locate.
