# Codex integration

Factory Log ships a portable instruction template at
`Integrations/agent-instructions.md`. The downloaded app can install the CLI and
append the template to `~/.codex/AGENTS.md` from Settings. The addition is
wrapped in `factory-log-managed` markers and never replaces existing content.

For manual setup:

```sh
zsh Scripts/install-cli.zsh
```

Then copy the contents of `Integrations/agent-instructions.md` into the global
or project `AGENTS.md` used by Codex. Start a small task and verify that its JSON
response and activity appear in Factory Log.

When Codex starts a task, the CLI records `CODEX_THREAD_ID` if it is available.
Active tasks with a valid UUID can open directly in Codex from their log row.
The integration does not copy prompts, transcripts, code, diffs, or terminal
output.

Factory Log does not require a Codex hook. If you build custom automation, keep
the same explicit start/report/archive semantics and never infer task completion
from prose.
