# Factory Log instructions for coding agents

Use `factorylog` to record the work you do in this project.

Start one task when you begin a meaningful piece of work:

```bash
factorylog start \
  --title "Add account settings" \
  --summary "Started the account settings screen." \
  --source cursor
```

Read the `event.taskID` value from the JSON response. Keep that ID for later updates.

Add a report after a meaningful result:

```bash
factorylog report \
  --task-id task_123 \
  --summary "Added profile editing and validation."
```

Archive the task when the requested work is finished:

```bash
factorylog archive \
  --task-id task_123 \
  --summary "Finished account settings and verified the build."
```

Write short factual summaries. Say what changed or what you verified. Do not include source code, diffs, command output, secrets, scores, or guessed progress percentages.

Keep a task open when work stops because of a blocker. Add a report that names the blocker instead of archiving the task.

Each successful command returns JSON on standard output. If a command fails, read the JSON error on standard error and correct the command.
