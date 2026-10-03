# Building and verification

## Requirements

- macOS 15 or newer
- Xcode 26, for Swift 6.2
- Optional: Ollama, to see day recaps
- Optional: Python 3, for the importers and the demo log

## Test

```sh
swift test
python3 -m py_compile Scripts/import-codex-work-log.py Scripts/import-git-history.py
```

## Build the app and CLI

```sh
zsh Scripts/build-app.zsh debug
zsh Scripts/build-app.zsh release
```

Release builds are universal by default. Set `FACTORYLOG_UNIVERSAL=0` for a quicker build for your own Mac only.

Release builds sign with Flavio's Developer ID when that certificate is in the keychain, and ad hoc otherwise. Set `FACTORYLOG_SIGN_IDENTITY` to override the identity, or to `-` for ad hoc on purpose.

The assembled app is `.build/Factory Log.app`. It contains the CLI at `Contents/Helpers/factorylog` and the agent templates under `Contents/Resources/Integrations`. Debug builds also include the snapshot hook in `DebugSnapshot.swift`, which release builds compile out.

## Verify the release contract

```sh
zsh Scripts/verify-release.zsh
```

This runs the tests, compiles the Python scripts, builds a universal release app, checks that the app and CLI versions agree, checks both architectures and the signature, writes 200 reports concurrently to a temporary store, checks that no tracked file mentions your home folder, and benchmarks loading 10,000 events.

## Build the release zip

```sh
zsh Scripts/build-release.zsh
```

This writes `dist/Factory-Log-<version>.zip` with `Factory Log.app` at its top. When the app is Developer ID signed, it notarizes with Apple, staples the ticket, recreates the zip, checks the signature survived zipping, and runs Gatekeeper assessment. It prints the SHA-256. [DISTRIBUTION.md](DISTRIBUTION.md) covers the rest of a release.

## Screenshots and banner

```sh
zsh Scripts/screenshots.zsh
swift Scripts/render-banner.swift
```

The screenshots come from `Scripts/make-demo-log.py`, four weeks of invented work, never from a real event log. The script quits Factory Log while it runs.
