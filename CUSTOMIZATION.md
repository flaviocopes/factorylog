# Customization

Work Tracebook is MIT-licensed and intended to be changed, rebranded, or used as a
starting point for another local activity product.

## Rebrand safely

Start with `FactoryLogProduct` in
`Sources/FactoryLogCore/FactoryLogProduct.swift`, then update:

- package, target, and executable names in `Package.swift`;
- display name, executable, bundle identifier, copyright, and version in
  `Resources/FactoryLog-Info.plist`;
- app and CLI paths in `Scripts/build-app.zsh` and release scripts;
- the GitHub repository passed to `AppUpdater.shared.start(repository:)` in
  `Sources/FactoryLogApp/FactoryLogApp.swift`, so updates come from your releases;
- app icon assets under `Resources/Assets.xcassets`;
- visible product copy and bundled integration templates;
- documentation examples and environment-variable prefix.

The bundle identifier, Application Support directory, CLI name, preference
keys, and environment prefix are persistence identifiers. Changing them after
shipping can orphan settings or create a second event store. Add an explicit
migration before renaming those values for existing users.

## Change the event model

Add optional fields when possible. Keep old fixtures readable and bump
`schemaVersion` only with a documented migration policy. Unknown source tool
identifiers already round-trip, so a new agent integration does not require a
schema change.

## Change the summary engine

Implement the `NarrativeEngine` protocol and inject it into `DayNarrator`.
Preserve the factual UI when inference is unavailable, use a new prompt version
when wording rules change, and include the selected model in cache validation.

## Build another interface

`FactoryLogCore` is independent of SwiftUI. A menu-bar app, export tool, server,
or another Apple-platform interface can reuse the models and queries. A remote
or multi-user service needs authentication, authorization, retention rules,
and a different concurrency/storage design.
