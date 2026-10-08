# Cursor integration

Work Tracebook ships a portable always-apply Cursor rule at
`Integrations/cursor-factory-log.mdc`. **Connect Cursor**, on the welcome
screen or in Settings, copies this rule to `~/.cursor/rules/factory-log.mdc`.

For manual setup:

```sh
zsh Scripts/install-cli.zsh
mkdir -p ~/.cursor/rules
cp Integrations/cursor-factory-log.mdc ~/.cursor/rules/factory-log.mdc
```

Restart Cursor if it does not notice the new rule, then run a small durable task
and confirm its reports appear. The shipped integration uses agent instructions
rather than private hooks or background services, so anyone can reproduce,
inspect, modify, and remove it.
