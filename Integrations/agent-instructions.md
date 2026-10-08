# Work Tracebook

Use `factorylog` for work that creates a durable outcome such as code,
configuration, content, documentation, a commit, or a deployment.

Before making changes:

```sh
factorylog start --title "<short title>" --summary "<what is starting>" --source <agent>
```

Preserve the returned `event.taskID`. After meaningful milestones:

```sh
factorylog report --task-id "<task ID>" --summary "<factual outcome>"
```

When the work is complete:

```sh
factorylog archive --task-id "<task ID>" --summary "<completed outcome>"
```

If work is blocked, report the blocker and leave the task open. Do not include
source code, diffs, command output, secrets, scores, or guessed percentages.
Do not log read-only answers, explanations, status checks, or abandoned attempts.
