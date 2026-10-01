# Codex integration

Factory Log ships a portable instruction template at
`Integrations/agent-instructions.md`. **Connect Codex**, on the welcome screen
or in Settings, appends it to `~/.codex/AGENTS.md`. The addition is wrapped in
`factory-log-managed` markers and never replaces existing content.

Codex runs commands in a sandbox that can only write inside the project, so
`factorylog` couldn't write the log on its own. **Connect Codex** also appends
this to `~/.codex/config.toml`, with your full home folder path:

```toml
[sandbox_workspace_write]
writable_roots = ["/Users/you/Library/Application Support/Factory Log"]
```

If the file already has a `[sandbox_workspace_write]` section, the app leaves it
alone and shows the line to add. Add the folder to that section's
`writable_roots` list yourself. Nothing is needed when Codex runs with
`danger-full-access`.

For manual setup:

```sh
zsh Scripts/install-cli.zsh
```

Then copy the contents of `Integrations/agent-instructions.md` into the global
or project `AGENTS.md` used by Codex, and add the sandbox section above. Start
a new Codex session, give it a small task that changes something, and check
that its reports appear in Factory Log.

When Codex starts a task, the CLI records `CODEX_THREAD_ID` if it is available.
Active tasks with a valid UUID can open directly in Codex from their log row.
The integration does not copy prompts, transcripts, code, diffs, or terminal
output.

Factory Log does not require a Codex hook. If you build custom automation, keep
the same explicit start/report/archive semantics and never infer task completion
from prose.
