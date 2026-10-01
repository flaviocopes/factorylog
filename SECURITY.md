# Security and privacy

## Data boundary

Factory Log records only the titles and summaries explicitly supplied by coding
agents. It does not inspect source code, Git history, diffs, terminal output, or
browser data. Events and cached narratives remain in the user's Application
Support directory.

Summaries may contain sensitive project information if an agent includes it.
Agent instructions therefore prohibit secrets, code, diffs, and command output.
Treat the event file as private work history and protect it with normal account
and backup controls.

History compaction is local, explicit, and irreversible. The settings screen
previews the number of removable records and asks for confirmation; keep a
backup when the original detailed summaries may still be needed.

## Concurrent writers

Factory Log writers coordinate through an interprocess lock. Keep mutations
inside `EventStore.appendValidated(_:)`; bypassing it can weaken task-state
validation even if a raw append remains offset-safe.

## Ollama and custom hosts

The default Ollama endpoint is loopback-only. Setting `FACTORYLOG_OLLAMA_HOST`
to another host sends project names, task titles, and summaries to that host.
Use HTTPS, trust the operator, and update product privacy copy before making a
remote host the default.

## Agent configuration

The app installs the CLI or agent instructions only after an explicit button
press. Codex instructions are appended inside a marked block. Review global
agent instructions before and after installation, especially when another tool
manages the same files.

## Release integrity

Releases on GitHub are universal and ad hoc signed, not Developer ID signed or
notarized. The README and the release notes explain the one-time
**Privacy & Security → Open Anyway** step, and every release lists the zip's
SHA-256.

The in-app updater only installs a release whose zip matches the SHA-256 digest
GitHub computed when it was uploaded, whose app has the same bundle identifier,
whose version matches the release tag, and whose code signature verifies,
nested code and both architectures included. When the app can't replace itself,
because it runs from App Translocation or its folder isn't writable, it offers
the release page instead.

Never commit or publish signing certificates, credentials, event logs, caches,
or local agent configuration. Screenshots and demos use the generated log from
`Scripts/make-demo-log.py`.
