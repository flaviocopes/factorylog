# Technical decisions

## Native SwiftUI and Swift Package Manager

The product is a small macOS utility, so SwiftUI provides native navigation,
accessibility, settings, and system appearance without a web runtime. SwiftPM
keeps the app, CLI, core, and tests buildable from one manifest. The tradeoff is
a manual app-bundle assembly script instead of an Xcode project.

## Append-only JSONL

Events remain inspectable and portable with ordinary text tools. Each line is
self-contained, and an interrupted final write cannot hide earlier history.
The tradeoff is that full-history queries scale linearly and record evolution
needs an explicit compatibility policy.

## Cross-process file locking

Several coding agents may report simultaneously. A sibling lock file protects
the complete validate-and-append transaction, while the data file uses append
semantics. This is intentionally simpler than adding a database and preserves
the public JSONL contract.

## Local inference is optional

Ollama summaries are best-effort presentation on top of factual events. The app
works without a model, never needs an API key, and caches generated sentences.
A non-loopback custom host is allowed for advanced users but changes the
privacy boundary and must be configured deliberately.

## Direct distribution outside the Mac App Store

Releases are universal apps with ad hoc signatures on GitHub, opened once
through the supported Gatekeeper override. This keeps distribution possible
without paid Apple Developer Program membership. App Sandbox would complicate
installing the CLI and reading agent configuration.

## Updates from GitHub Releases

The app updates itself from the latest GitHub release with one dependency-free
file and no signing keys. It trusts GitHub's upload digest, then checks the
bundle identifier, version, and code signature before swapping the app in
place. The tradeoff is a strict release contract: tag, versions, and zip layout
have to match, because installed copies keep the checks they shipped with.
