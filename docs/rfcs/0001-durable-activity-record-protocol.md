# DARP 0001: Durable Activity Records for Developer Work

| Field | Value |
| --- | --- |
| Status | Draft |
| Category | Standards Track |
| Version | 1.0.0-draft.1 |
| Date | August 2026 |
| Editor | Flavio Copes |

## Status of this document

This is a project Request for Comments. It uses familiar RFC conventions, but it is not an IETF publication or Internet Standard.

Discussion and implementations are welcome. Version 1 stays a draft until at least two independent producers and two independent consumers can exchange the same records.

## Abstract

Developer work now happens across people, coding agents, editors, terminals, CI systems, and project tools. Each system can show part of the work, but there is no small shared format for saying, “this task moved forward, and here is the durable outcome.”

The **Durable Activity Record Protocol**, or **DARP**, defines that format.

A DARP producer emits short, factual records at meaningful task transitions. A consumer can store those records, build a daily chronicle, count activity, or show project momentum. The protocol records claims about outcomes. It does not inspect source code, collect terminal output, or assign a productivity score.

The key idea is simple:

> Measure meaningful reported outcomes, not keystrokes, tokens, files, or busyness.

## 1. Introduction

Common developer metrics usually start from what a tool can observe. They count commits, pull requests, lines changed, tickets closed, deployments, or time spent in an editor.

Those signals can help. They also miss planning, debugging, documentation, research, configuration, review, and changes made by AI agents. Worse, they invite people to optimize the measurement instead of the work.

DARP starts from a different primitive: the **durable activity record**.

A durable activity record says that a task started, reached a meaningful milestone, became blocked, completed, or stopped. It includes enough context to group the record by task and project. It also carries a short outcome summary written for a person.

DARP standardizes the record, its lifecycle, and the way activity counts are derived. It does not standardize a dashboard, command-line interface, storage engine, transport, or management score.

Factory Log is the first reference application. It is not part of the protocol.

## 2. Goals

DARP has six goals:

1. Let humans and software agents report work through the same format.
2. Make records portable across tools and readable without a specific app.
3. Count meaningful task activity without reading source code or surveillance data.
4. Preserve a chronological explanation of what changed.
5. Support local-first, append-oriented storage and concurrent producers.
6. Keep the core small enough to implement in an afternoon.

## 3. Non-goals

DARP does not try to:

- prove that an outcome is correct or valuable;
- measure the full productivity of a person or team;
- replace DORA, SPACE, DevEx, or business outcome metrics;
- record every tool call, file edit, command, prompt, or token;
- move source code, diffs, terminal output, or secrets;
- define task planning, assignment, priority, or percentage complete;
- define a network transport or central service;
- create an employee-ranking system.

## 4. Conventions and terminology

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**, and **MAY** are interpreted as described by [BCP 14](https://www.rfc-editor.org/info/bcp14) when, and only when, they appear in capitals.

### 4.1 Producer

A **producer** creates a DARP record. A producer can be a person, coding agent, editor extension, command-line tool, CI job, or adapter.

The producer reports a claim. The producer does not need to be the only contributor to the work.

### 4.2 Consumer

A **consumer** reads DARP records. A consumer can validate, store, aggregate, display, export, or relay them.

### 4.3 Ledger

A **ledger** is an ordered collection of accepted records. A newline-delimited local file is a ledger. A database table or remote event stream can also be a ledger.

### 4.4 Task

A **task** is a bounded thread of work with one lifecycle. It starts once and ends at most once.

### 4.5 Durable outcome

A **durable outcome** remains useful or observable after the work session ends.

Examples include:

- code, configuration, content, or documentation saved to a project;
- a reviewed decision or plan saved for later use;
- a completed code review with actionable feedback;
- a deployment or external project-system change;
- an investigation that resolves uncertainty and changes the next decision;
- a verified repair, migration, or release.

Reading a file, running a command, invoking a tool, generating tokens, or thinking about a problem is not a durable outcome by itself.

### 4.6 Meaningful milestone

A **meaningful milestone** is the smallest coherent outcome worth telling a collaborator about.

One file edit is usually too small. “Added validation, migration fixtures, and tests for schema version 2” is a meaningful milestone.

### 4.7 Effective record

An **effective record** is a valid record that remains after duplicate removal and amendments are applied.

## 5. The protocol model

DARP uses immutable event records. Each record belongs to one project and one task.

A task follows this lifecycle:

```text
missing --started--> active
active --progressed--> active
active --blocked--> blocked
blocked --progressed--> active
active | blocked --completed--> completed
active | blocked --abandoned--> abandoned
```

The record kinds are:

| Kind | Meaning | Counts as outcome activity |
| --- | --- | --- |
| `task.started` | The producer committed to a task. | No |
| `task.progressed` | The task reached a meaningful durable milestone. | Yes |
| `task.blocked` | Work cannot continue without new input or external change. | No |
| `task.completed` | The requested outcome was delivered. | Yes |
| `task.abandoned` | The task stopped without completion. | No |

`task.progressed` moves a blocked task back to active. `task.completed` and `task.abandoned` are terminal.

An amendment can replace or retract an earlier record. Amendments preserve the historical record while fixing the effective view.

Lifecycle rules apply to normal records. An amendment carries its target's kind for validation, but it does not repeat that lifecycle transition.

## 6. Record format

A DARP record is a UTF-8 JSON object conforming to [RFC 8259](https://www.rfc-editor.org/info/rfc8259).

An encoded record MUST NOT exceed 65,536 bytes. This limit keeps local tools predictable and gives network bindings a common minimum capacity.

The normative JSON Schema is [darp-1.0.schema.json](schema/darp-1.0.schema.json).

Example:

```json
{
  "specVersion": "1.0",
  "id": "019cb40b-b30e-72f2-8fb1-2c413b9f544a",
  "sequence": 2,
  "previousID": "019cb409-79d2-7f31-9f52-7b1a63128b97",
  "occurredAt": "2026-08-28T15:12:00+02:00",
  "recordedAt": "2026-08-28T15:12:03+02:00",
  "kind": "task.progressed",
  "project": {
    "id": "urn:uuid:eb0d9db1-82aa-4d44-8e45-a71452c0214c",
    "name": "Factory Log"
  },
  "task": {
    "id": "task_6b8d9c1780e24ac5a76c88f52fb51d35",
    "title": "Define developer activity protocol"
  },
  "source": {
    "tool": "codex",
    "sessionID": "019cb408-76c9-7c2d-92f5-3c650e643b72"
  },
  "summary": "Defined the task lifecycle, activity measure, and privacy boundary.",
  "outcome": {
    "category": "documentation",
    "verification": {
      "status": "verified",
      "methods": ["manual-review"]
    }
  }
}
```

### 6.1 `specVersion`

`specVersion` identifies the DARP major and minor version. Producers conforming to this document MUST use `1.0`.

Patch changes clarify the specification and do not change this value.

### 6.2 `id`

`id` uniquely identifies the record. Producers MUST NOT reuse an ID for a different record.

A UUID conforming to [RFC 9562](https://www.rfc-editor.org/info/rfc9562) is RECOMMENDED. UUIDv7 is useful when an implementation also wants roughly time-sortable identifiers.

Consumers MUST treat a repeated `id` as a duplicate. If the repeated content differs, the consumer MUST surface an integrity error.

### 6.3 `sequence`

`sequence` is a positive integer scoped to the pair `(project.id, task.id)`.

The start record MUST use `1`. Each later record MUST increment the last accepted sequence by one.

The largest valid sequence is 9,007,199,254,740,991 so it round-trips safely through common JSON implementations.

Sequence numbers define task order. Timestamps do not.

### 6.4 `previousID`

The start record MUST omit `previousID`. Every later record MUST set `previousID` to the preceding accepted record ID for that task.

The sequence and previous ID form a small causal chain. They let a consumer detect missing records and concurrent writers without relying on synchronized clocks.

### 6.5 `occurredAt`

`occurredAt` records when the reported activity happened. It MUST be an RFC 3339 timestamp with an explicit UTC offset.

Activity views use this field to place work in a time window.

### 6.6 `recordedAt`

`recordedAt` records when the producer created the record. It MUST be an RFC 3339 timestamp with an explicit UTC offset.

For live reporting, `occurredAt` and `recordedAt` will usually be close. Importers MAY preserve an older `occurredAt` while setting `recordedAt` to the import time.

### 6.7 `kind`

`kind` declares the lifecycle transition described in Section 5.

A producer MUST NOT emit `task.progressed` for routine operations. It emits one only after a meaningful milestone.

### 6.8 `project`

`project.id` is a stable, opaque identifier. It MUST stay stable when the project moves to a different local path.

`project.name` is the human-readable name.

`project.locator` is OPTIONAL. When present, it MUST be a URI. A local app can use a `file:` URI, but it SHOULD omit that locator from shared exports because paths often reveal usernames and directory structures.

### 6.9 `task`

`task.id` is stable inside the project. `task.title` is a short human-readable description.

The unique task key is `(project.id, task.id)`. Consumers MUST NOT assume a task ID is globally unique by itself.

### 6.10 `source`

`source.tool` names the reporting tool. Values are open strings so a new agent or editor does not require a protocol revision.

`source.sessionID` is OPTIONAL. It links back to a session when the source exposes a safe, stable identifier.

The source says who produced the record. It does not claim sole authorship of the outcome.

### 6.11 `summary`

`summary` is a short factual description written for a person.

For `task.progressed` and `task.completed`, it SHOULD start with the outcome: “Added,” “Fixed,” “Documented,” “Deployed,” or another concrete past-tense verb.

A summary MUST NOT contain:

- source code or diff hunks;
- raw terminal output or prompts;
- credentials, tokens, or other secrets;
- a guessed percentage complete;
- a score assigned to a person.

### 6.12 `outcome`

`outcome` is REQUIRED for normal and replacement `task.progressed` and `task.completed` records. A retraction and every other kind MUST omit it.

`outcome.category` is an open lowercase token. Version 1 defines these common values:

- `code`
- `configuration`
- `content`
- `decision`
- `deployment`
- `documentation`
- `external-change`
- `plan`
- `review`
- `other`

Applications MAY define namespaced categories such as `com.acme.security-review`.

`outcome.verification.status` is either `verified` or `not-verified`. A verified outcome MUST include at least one method. Common methods include `automated-tests`, `build`, `lint`, `manual-review`, `runtime-check`, `deployment-check`, and `external-acknowledgement`.

Verification remains a producer claim. A DARP record is not cryptographic proof.

### 6.13 `amendment`

`amendment` fixes an earlier record without rewriting history.

It contains:

- `targetID`: the record being amended;
- `action`: `replace` or `retract`;
- `reason`: a short explanation.

An amendment MUST use the same project, task, and kind as its target. It MUST target the current effective version of that record. It still takes the next task sequence number and points `previousID` at the latest accepted record.

For `replace`, the new record replaces the target in effective views. It carries the corrected summary and, when required by the kind, a corrected outcome. For `retract`, neither the target nor the amendment contributes to activity metrics, and the amendment omits `outcome`.

A replacement SHOULD preserve the target's `occurredAt` unless the timestamp itself was wrong. A start record MUST NOT be retracted while later effective records exist. Retracting the only record removes the empty task from effective views.

An amendment does not repeat the target's lifecycle transition. It only changes the effective record.

### 6.14 `extensions`

`extensions` carries optional application data. Every extension key MUST use a reverse-domain name, such as `dev.factorylog.threadURL`.

Consumers MUST preserve unknown extensions when relaying a full record. Consumers MUST NOT change core behavior based on an unknown extension.

Sensitive values SHOULD NOT be placed in extensions.

## 7. Producer behavior

A conforming producer MUST:

1. Emit exactly one normal `task.started` record before other task records.
2. Use contiguous sequence numbers and the correct previous record ID.
3. Emit `task.progressed` only for meaningful milestones.
4. Emit no records after a terminal record, except amendments.
5. Keep summaries factual and free of prohibited content.
6. Reuse the same record ID when retrying an uncertain delivery.

A producer SHOULD report soon after the outcome occurs. It SHOULD combine tightly related edits, tests, and documentation into one milestone.

A producer MUST NOT create one activity record per command, file, commit, token interval, or elapsed-time interval. Those patterns measure instrumentation volume, not useful output.

## 8. Consumer and ledger behavior

A conforming consumer MUST validate the JSON shape and task lifecycle before accepting a record.

For each task, it MUST check:

- sequence `1` is a normal `task.started` record;
- later sequences are contiguous;
- `previousID` matches the prior accepted record;
- no normal record follows completion or abandonment;
- blocked, completed, and abandoned transitions start from a valid state;
- amendments point to an existing record in the same task.

A consumer MUST make invalid records visible to the operator. It MUST NOT silently reinterpret them as valid records.

A ledger SHOULD append accepted records atomically. When several producers can write at once, the ledger MUST serialize validation and append as one transaction.

If two different records claim the same next sequence, the ledger MUST accept at most one. The losing producer can reload the task head and retry with a new sequence and ID.

A consumer MAY compact old detail. If it does, it MUST preserve enough information to reproduce every published aggregate, and it MUST disclose which narrative detail is no longer available.

## 9. Serialization and exchange

### 9.1 Single record

A single record is serialized as one JSON object.

### 9.2 Local or append-oriented stream

A local ledger MAY use newline-delimited JSON with one complete record per line and a final newline. String line breaks MUST be escaped so a physical line contains exactly one record.

The RECOMMENDED file extension is `.jsonl`. This profile favors simple inspection and recovery with common command-line tools.

Implementations that need the registered `application/json-seq` media type MAY use the record separator format defined by [RFC 7464](https://www.rfc-editor.org/info/rfc7464).

### 9.3 Transport

DARP is transport-independent. A record can travel through standard input and output, a local socket, HTTP, a message queue, or file synchronization.

Transport bindings are separate specifications. They MUST preserve the complete record and MUST NOT weaken validation rules.

### 9.4 CloudEvents binding

Systems that already use [CloudEvents 1.0](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md) MAY place the complete DARP record in `data`.

The binding uses:

| CloudEvents attribute | DARP value |
| --- | --- |
| `specversion` | `1.0` |
| `id` | DARP `id` |
| `source` | A URI identifying the DARP producer |
| `type` | `dev.darp.` plus the DARP `kind` |
| `subject` | `project.id` plus `task.id` |
| `time` | DARP `recordedAt` |
| `datacontenttype` | `application/json` |
| `data` | The complete DARP record |

DARP does not require CloudEvents. The binding exists to avoid inventing another envelope where one already exists.

## 10. Activity measurement profile

DARP measures **reported outcome activity**. It does not measure total productivity.

This distinction matters. The [SPACE framework](https://www.microsoft.com/en-us/research/publication/the-space-of-developer-productivity-theres-more-to-it-than-you-think/) shows that developer productivity has several dimensions and cannot be reduced to one activity metric. [DORA](https://dora.dev/guides/dora-metrics/) measures software delivery throughput and stability at the application or service level. DARP complements those approaches with a portable personal or project chronicle.

### 10.1 Input set

An activity view MUST declare:

- the inclusive start and exclusive end timestamps;
- the IANA time zone used for calendar days;
- project filters, if any;
- source filters, if any;
- whether late-arriving records are included;
- whether compacted aggregates are included.

The view MUST validate records, remove duplicates, and apply amendments before counting.

### 10.2 Core measures

For an input set of effective records, DARP defines:

| Measure | Definition |
| --- | --- |
| `activityCount` | Number of `task.progressed` and `task.completed` records whose `occurredAt` falls in the window. |
| `tasksTouched` | Number of distinct task keys with any effective record in the window. |
| `completedTasks` | Number of effective `task.completed` records in the window. |
| `blockedTasks` | Number of tasks whose last effective record at the window end is `task.blocked`. |
| `verifiedOutcomes` | Number of counted activity records with verification status `verified`. |
| `activeDays` | Number of local calendar days containing at least one counted activity record. |

The list of human-readable outcome summaries is part of the view. Counts without their outcomes lose the most useful context.

### 10.3 Daily Activity Statement

A **Daily Activity Statement** is the standard personal view for one local calendar day.

Example:

```json
{
  "date": "2026-08-28",
  "timeZone": "Europe/Paris",
  "activityCount": 3,
  "tasksTouched": 2,
  "completedTasks": 1,
  "blockedTasks": 0,
  "verifiedOutcomes": 2,
  "outcomes": [
    "Defined the DARP lifecycle and record format.",
    "Added a machine-readable schema and valid example stream.",
    "Published the protocol from the Factory Log documentation."
  ]
}
```

This object is an application view, not a DARP wire record.

### 10.4 Interpretation

Higher activity can mean more meaningful milestones. It can also mean smaller task boundaries, easier work, or a more talkative producer.

For this reason, a conforming activity view:

- MUST label the measure as activity, outcomes, or momentum;
- MUST NOT label `activityCount` as a productivity score;
- MUST keep outcome summaries available beside counts;
- SHOULD compare the same person or project with its own history;
- SHOULD use trends as prompts for reflection, not targets;
- MUST NOT use DARP counts alone to rank, compensate, discipline, or evaluate people.

The protocol gives us a shared ruler. It does not decide what is worth building.

## 11. Privacy and data minimization

DARP is designed for semantic reports, not behavioral surveillance.

A conforming core record MUST NOT contain source code, diffs, raw terminal output, prompts, credentials, or secrets. Producers SHOULD collect the smallest amount of identity and location data needed by the application.

Local filesystem paths are sensitive. Session IDs can also become correlators across exports. Exporters SHOULD remove `project.locator`, `source.sessionID`, and private extensions unless the user explicitly includes them.

Applications SHOULD default to local storage. Remote synchronization requires a visible destination, retention policy, and access model.

## 12. Security considerations

DARP records are claims supplied by producers. A malicious or misconfigured producer can fabricate outcomes, verification, timestamps, identities, and task history.

Consumers MUST validate structure and lifecycle, but validation does not establish truth.

Implementations SHOULD:

- restrict who can append to a ledger;
- use atomic writes and cross-process locking for local files;
- authenticate remote producers;
- encrypt records in transit;
- cap record size before parsing;
- reject invalid UTF-8 and malformed JSON;
- avoid rendering summaries as HTML;
- escape values before displaying or exporting them;
- keep a visible audit trail for amendments.

Append-only storage improves recoverability. It does not make a ledger tamper-proof. Digital signatures and hash-chain integrity are candidates for a future extension.

## 13. Versioning and extensions

Version 1 consumers MUST accept `specVersion` equal to `1.0`.

New optional behavior belongs in namespaced extensions. A change that removes a field, changes a field's meaning, changes lifecycle semantics, or makes an optional field required needs a new major version.

Consumers receiving an unsupported major version MUST preserve the raw record when safe, report the unsupported version, and exclude the record from derived metrics.

## 14. Conformance

An implementation can claim one or more roles.

### 14.1 DARP 1.0 producer

A conforming producer:

- emits records valid against the version 1 schema;
- follows task lifecycle and chaining rules;
- reports meaningful milestones instead of tool operations;
- follows the content and privacy restrictions.

### 14.2 DARP 1.0 consumer

A conforming consumer:

- validates records and surfaces errors;
- deduplicates by record ID;
- derives state from sequence and previous ID;
- applies amendments;
- preserves unknown namespaced extensions when relaying records.

### 14.3 DARP 1.0 activity view

A conforming activity view:

- publishes its time window, time zone, and filters;
- computes the core measures exactly as defined;
- keeps outcome text available;
- follows the interpretation safeguards in Section 10.4.

## 15. Factory Log application profile

Factory Log schema version 1 predates DARP. It already implements the central idea, but it is not wire-compatible without an adapter.

The mapping is:

| Factory Log v1 | DARP 1.0 |
| --- | --- |
| `schemaVersion` | Adapter emits `specVersion` |
| `id` | `id` |
| File order per task | Adapter derives `sequence` and `previousID` |
| `timestamp` | `occurredAt`; export time becomes `recordedAt` |
| `task.started` | `task.started` |
| `task.reported` | `task.progressed` |
| Explicit `task.archived` | `task.completed` when completion was claimed |
| Automatic or non-completion archive | `task.abandoned` |
| `project.path` | Local project identity; export SHOULD replace it with an opaque `project.id` |
| `project.name` | `project.name` |
| `taskID`, `taskTitle` | `task.id`, `task.title` |
| `source` | `source` |
| `summary` | `summary` |

Factory Log currently counts every stored lifecycle event as an update. A strict DARP activity view counts only progressed and completed outcomes. The two values SHOULD have different labels until Factory Log implements the DARP measurement profile.

Factory Log remains free to use JSONL, local storage, a macOS dashboard, and its own command-line interface. Those are application choices, not protocol requirements.

## 16. Related work

DARP builds on existing ideas instead of replacing them:

- [ActivityStreams 2.0](https://www.w3.org/TR/activitystreams-core/) defines a rich JSON model for social activities. DARP has a narrower developer-work lifecycle and measurement profile.
- [CloudEvents](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md) defines a portable event envelope. DARP can use it as a binding.
- [W3C PROV-O](https://www.w3.org/TR/prov-o/) models entities, activities, agents, and provenance. DARP uses a smaller operational record and can be mapped to PROV later.
- [OpenTelemetry events](https://opentelemetry.io/docs/specs/semconv/general/events/) describe meaningful point-in-time occurrences. DARP applies the idea to durable developer outcomes without becoming telemetry.
- [SPACE](https://www.microsoft.com/en-us/research/publication/the-space-of-developer-productivity-theres-more-to-it-than-you-think/) frames productivity across satisfaction, performance, activity, communication, and efficiency. DARP covers only a careful part of the activity dimension.
- [DORA](https://dora.dev/guides/dora-metrics/) measures software delivery performance through throughput and instability. DARP records work before, after, and outside deployment.

The related standards reviewed for this draft do not define the same combination of agent-issued outcome records, task lifecycle, local-first privacy boundary, and activity measurement profile.

## 17. IANA considerations

This draft requests no IANA action. DARP does not register a media type.

## 18. Open questions before 1.0

The draft needs implementation feedback on:

1. Whether `task.blocked` belongs in the core lifecycle.
2. Whether `sequence` and `previousID` are both worth their cost.
3. Whether verification needs a registry of common methods.
4. Whether a standard HTTP binding would improve interoperability.
5. Whether signed records and hash chaining belong in a separate integrity profile.
6. How compacted ledgers should exchange historical aggregates.
7. Whether project identity needs a standard derivation method.

## 19. Reference files

- [Normative JSON Schema](schema/darp-1.0.schema.json)
- [Example task stream](examples/darp-task.jsonl)
