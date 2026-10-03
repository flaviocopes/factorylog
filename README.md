<img src="docs/banner.png" alt="Factory Log, a timeline of what your coding agents did" />

Factory Log shows what your coding agents did for you: a timeline of each day and each week, and where your time went, project by project. Codex, Cursor or any other agent writes a one-line report when it finishes something, and the report shows up in the app a second later.

When agents work across five projects in a day, it's hard to say in the evening what actually happened. Factory Log keeps that record for you, written by the agents themselves, in a plain file on your Mac. It never reads your code, your diffs or your terminal.

## Download

Get `Factory-Log-1.2.0.zip` from the [latest release](https://github.com/flaviocopes/factorylog/releases/latest), unzip it, and drag Factory Log to your Applications folder. It runs on macOS 15 Sequoia or later, on Apple silicon and Intel Macs.

### Opening it the first time

Factory Log is signed with my Apple Developer ID and notarized by Apple. The first time you open it, macOS asks if you're sure you want to open an app downloaded from the internet. Click **Open**.

On a work laptop you might not be able to install apps in `/Applications`. You can keep Factory Log in the `Applications` folder inside your home folder instead.

### Updates

Once a day, Factory Log asks GitHub whether there's a newer version. When there is, it shows what's new, and **Install and Relaunch** puts it in place of the old one. **Factory Log → Check for Updates…** checks right away.

To turn off the daily check, run this in Terminal:

```sh
defaults write dev.factorylog.app AppUpdaterAutomaticChecks -bool false
```

## Set it up

Agents don't talk to the app directly. Each one runs a small command, `factorylog`, which adds a line to a log file on your Mac, and the app shows the new line a second later. So setting up comes down to two things: the agent can run `factorylog`, and it knows when to.

The first time you open Factory Log, it walks you through three steps:

1. **Install the command-line tool.** The app copies `factorylog` to `~/.local/bin`. Then it asks your login shell whether it can find the command there, because agents get their `PATH` from that shell. If it can't, and you use zsh, the macOS default, **Add to PATH** adds the folder to `~/.zshenv`.
2. **Connect your agent.** For Codex, one click adds a short instruction to `~/.codex/AGENTS.md`. It also adds the log folder to Codex's sandbox in `~/.codex/config.toml`, so `factorylog` is allowed to write to it. For Cursor, it adds a rule to `~/.cursor/rules`. The instruction tells the agent when to report, and what never to include.
3. **Ask an agent to build something.** Agents report work that changes something, like a fix, a feature or new docs. Questions and explanations aren't logged. The first report lands a second later, and the welcome screen turns into your day. **Send a test report** checks the command and the log without waiting for an agent.

<img src="docs/screenshot-welcome-light.png" alt="The Factory Log welcome screen with the three setup steps" />

The same buttons live in **Settings → Integrations**, for when you add an agent later.

### Other agents

Any agent that can run shell commands can report. Click **Copy the instructions** on the welcome screen or in Settings, and paste them where your agent keeps its standing instructions:

- Claude Code reads `~/.claude/CLAUDE.md`.
- Gemini CLI reads `~/.gemini/GEMINI.md`.
- Most other agents read an `AGENTS.md` file at the root of each project.

If the agent runs commands in a sandbox, it also needs permission to write to `~/Library/Application Support/Factory Log`.

### If reports don't show up

Go through these in order:

1. **Check that your shell finds the command.** Open a new Terminal window and run `command -v factorylog`. It should print a path that ends in `.local/bin/factorylog`. If it prints nothing, add the folder to your `PATH`:

   ```sh
   # zsh, the macOS default
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv

   # fish
   fish_add_path ~/.local/bin
   ```

   On bash, add the same `export` line to `~/.bash_profile`. Then restart your agent, so it picks up the new `PATH`.
2. **Send a test report** from **Settings → Integrations**. If it shows up in Today, the command and the app both work, and the problem is on the agent's side.
3. **Start a new agent session.** Agents read their instructions when a session starts, so a session that was already open hasn't seen them. Cursor might need a restart to notice a new rule.
4. **Check Codex's sandbox.** If Codex can't write the log, open `~/.codex/config.toml` and make sure the log folder is in its writable roots, written out in full:

   ```toml
   [sandbox_workspace_write]
   writable_roots = ["/Users/you/Library/Application Support/Factory Log"]
   ```

   If the file already has a `[sandbox_workspace_write]` section, add the path to its `writable_roots` list. The app leaves an existing section alone, so this is the case it can't fix for you.
5. **Ask for real work.** A question, an explanation or a status check isn't logged, by design.

## Features

- **What I did today, and yesterday.** Each day opens with your active time, the projects you touched and the tasks agents finished. A timeline shows one lane per project across the hours, with a bar for every work session. Hover a bar to see its tasks.
- **Every task, once.** The log lists each task with its latest report, newest first. Tasks still open say **Doing**, and you can close one with a final outcome.
- **A one-line recap per project.** Finished days get a sentence for each project, written by a local [Ollama](https://ollama.com) model if you have one. Without it you see the task titles instead.
- **Your week at a glance.** One row per day, one bar per session, colored by project. Next to it, a donut of where the week went and the list of what shipped. Step back through earlier weeks with the arrows.
- **The long view.** Insights shows your time by project over the last 7, 30 or 90 days or all time, a 26-week heatmap and the busiest projects. Click a project to open a panel with its time, its daily rhythm and every task you did there.
- **Live.** The app watches the log, so new reports appear on their own. There's no refresh button.
- **Hide what doesn't matter.** Right-click a project to hide it, and bring it back from Settings. Work done inside an agent's own folder, like `~/.cursor` or `~/.codex`, never shows up.
- **Keyboard.** ⌘1 to ⌘4 switch between Today, Yesterday, Week and Insights. The arrow keys switch between a day's summary and its log, or between weeks. Esc steps back out.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-today-dark.png" />
  <img src="docs/screenshot-today-light.png" alt="Today in Factory Log: active time, a timeline of work sessions per project, and every task" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-week-dark.png" />
  <img src="docs/screenshot-week-light.png" alt="The week view: a row per day with work sessions colored by project, the split of time per project, and what shipped" />
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-insights-dark.png" />
  <img src="docs/screenshot-insights-light.png" alt="Insights with time by project, a 26-week heatmap, and a project's panel listing every task" />
</picture>

## The command line

Agents call three commands. You can call them too:

```sh
factorylog start --title "Add account settings" --summary "Started the settings screen." --source codex
factorylog report --task-id task_123 --summary "Added validation and tests."
factorylog archive --task-id task_123 --summary "Finished and verified account settings."
```

`start` returns the task ID in its JSON output, and the other two use it. Every command prints JSON, takes `--store` to write to another log and `--timestamp` to record a past time, and `factorylog --help` lists the rest. A task left open for 24 hours is marked Done automatically.

## Privacy

Everything Factory Log records stays on your Mac, in `~/Library/Application Support/Factory Log/`. There are no accounts, no analytics and no server.

The app goes online in two cases. Once a day it asks GitHub whether there's a newer version, and it downloads one only when you click **Install and Relaunch**. If you run Ollama, it sends a finished day's report text to it to write the recaps, which stays on your Mac unless you point `FACTORYLOG_OLLAMA_HOST` at another machine.

The reports are whatever your agents write. The instructions Factory Log installs tell them never to include code, diffs, command output or secrets. [PRIVACY.md](PRIVACY.md) has the details.

## How it works

Factory Log is one Swift package with three parts. `FactoryLogCore` holds the data model, the event store and every query. The `factorylog` command and the SwiftUI app are both thin clients of it, so they can't disagree about what's in the log.

### The log is a text file

Every report is one line of JSON in `events.jsonl`, with the task, the project folder, the agent, a timestamp and the sentence the agent wrote. Lines are only ever added. Correcting something means adding a new report, and closing a task means adding an archive line. You can read the whole history with `cat`, and [docs/event-contract.md](docs/event-contract.md) describes the format.

### Several agents can write at once

Before writing, the CLI takes an exclusive `flock` on a lock file next to the log. Under that lock it rereads the log and checks the report makes sense: the task exists, isn't closed, and keeps its project and title. Then it appends one line and calls `fsync`. Readers take a shared lock. A line cut short by a crash is skipped, and a malformed or future-version line is reported by line number while the rest of the history stays readable.

### The app watches the file

A file-system dispatch source tells the app when the log grows, and it reloads in the background. On each reload it also archives any task that has been open for 24 hours, under the same lock.

### Time is estimated, not tracked

Agents report outcomes, not hours, so Factory Log infers the time from when reports arrive. Within a project, reports at most 45 minutes apart form one work session, and each session gets 5 extra minutes for the work before its first report. Those sessions are the bars in every timeline, and their lengths add up to the active time. Each project is measured on its own, so two agents working in parallel count toward both projects.

### Recaps are cached

For a finished day, Factory Log sends each project's reports to a local Ollama model (`gemma3:4b` by default) and asks for one plain sentence. The sentence is saved in `narratives.json` with a signature of the reports it came from. A new report changes the signature, so a stale recap gets rewritten. The numbers and task titles always come from the log, never from the model.

### Updates verify what they install

The updater downloads the release zip next to the app and compares its SHA-256 with the digest GitHub computed at upload. It checks that the bundle ID, the version and the code signature match before it swaps the app in place and relaunches it.

[ARCHITECTURE.md](ARCHITECTURE.md) goes deeper into the targets, the data flow and how storage recovers from problems.

## Build it from source

You need macOS 15 or later and Xcode 26, for Swift 6.2.

```sh
swift test
zsh Scripts/build-app.zsh debug
open ".build/Factory Log.app"
```

To build the release zip, run:

```sh
zsh Scripts/build-release.zsh
```

It builds a universal app, signs it with my Developer ID when that certificate is in the keychain (ad hoc everywhere else), notarizes when signed that way, and zips it into `dist/`.

A copy you build yourself opens without a warning on your Mac. If you send it to another Mac, macOS says it "could not verify Factory Log is free of malware". Click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or remove the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Factory Log.app"
```

## Development

```sh
zsh Scripts/verify-release.zsh         # tests, a universal release build, signatures, 200 concurrent writers
zsh Scripts/screenshots.zsh            # the screenshots in docs/, from a generated demo log
swift Scripts/render-banner.swift      # docs/banner.png
python3 Scripts/make-demo-log.py /tmp/demo/events.jsonl   # four weeks of made-up work
```

Point the app or the CLI at another log with `FACTORYLOG_EVENTS_FILE=/absolute/path/events.jsonl`. [CONFIGURATION.md](CONFIGURATION.md) lists every setting, and [CUSTOMIZATION.md](CUSTOMIZATION.md) covers forking and rebranding.

Two optional scripts fill gaps in your history. `Scripts/import-git-history.py` turns runs of your Git commits into tasks, and `Scripts/import-codex-work-log.py` imports an older plain-text work log. Run either with `--help` first, and `--dry-run` where it's offered. When `cursor-agent` is installed, the Git importer asks it to write task titles, which sends your commit subjects to Cursor. Pass `--no-titles` to keep everything local.

Working with an AI coding agent? Point it at [AGENTS.md](AGENTS.md). It has the commands and the rules to follow.

## License

[MIT](LICENSE)
