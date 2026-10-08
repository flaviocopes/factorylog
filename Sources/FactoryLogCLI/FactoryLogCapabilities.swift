import Foundation
import FactoryLogCore

enum FactoryLogCapabilities {
    struct Manifest: Encodable {
        struct Capability: Encodable {
            let description: String
            var command: String? = nil
        }

        struct Release: Encodable {
            let version: String
            let date: String
            let changes: [String]
        }

        let name: String
        let version: String
        let summary: String
        let capabilities: [Capability]
        let changelog: [Release]
    }

    static let manifest = Manifest(
        name: "factorylog",
        version: FactoryLogVersion.current,
        summary: "Records agent task starts, progress reports, and archives in Work Tracebook's local event log.",
        capabilities: [
            Manifest.Capability(
                description: "Start a new task in the Work Tracebook event log",
                command: "factorylog start --title \"Add account settings\" --summary \"Started the settings screen.\" --source cursor"
            ),
            Manifest.Capability(
                description: "Report progress on an open task",
                command: "factorylog report --task-id task_abc123 --summary \"Added validation and tests.\""
            ),
            Manifest.Capability(
                description: "Archive a finished task with a final summary",
                command: "factorylog archive --task-id task_abc123 --summary \"Shipped account settings and verified in the app.\""
            ),
            Manifest.Capability(
                description: "Tag the project path and name when starting work",
                command: "factorylog start --title \"Fix login\" --summary \"Investigating the redirect.\" --project-path /Users/you/dev/myapp --project-name myapp"
            ),
            Manifest.Capability(
                description: "Write events to another log file for testing",
                command: "factorylog start --title \"Dry run\" --summary \"Testing the CLI.\" --store /tmp/factorylog-test/events.jsonl"
            ),
            Manifest.Capability(
                description: "Backdate an event with an RFC 3339 timestamp",
                command: "factorylog report --task-id task_abc123 --summary \"Caught up after import.\" --timestamp 2026-10-01T14:30:00Z"
            )
        ],
        changelog: [
            Manifest.Release(version: "1.3.0", date: "2026-10-08", changes: ["Renamed the app to Work Tracebook. Existing commands and saved data still work."]),
            Manifest.Release(
                version: "1.2.0",
                date: "2026-10-03",
                changes: ["Signed and notarized Mac app. The CLI didn't change."]
            ),
            Manifest.Release(
                version: "1.1.0",
                date: "2026-10-01",
                changes: [
                    "Setup checks that agents can find factorylog on PATH.",
                    "Codex sandbox can include the log folder.",
                    "Send a test report from the app without waiting for an agent."
                ]
            ),
            Manifest.Release(
                version: "1.0.0",
                date: "2026-10-01",
                changes: [
                    "First release: start, report, and archive append JSON lines to the shared event log.",
                    "Optional --store, --timestamp, --source, and --session-id on every command."
                ]
            )
        ]
    )

    static func printManifest(json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(manifest), as: UTF8.self))
            return
        }

        print("\(manifest.name) \(manifest.version)\n\(manifest.summary)\n\nWhat it can do:")
        for capability in manifest.capabilities {
            print("  \(capability.description)")
            if let command = capability.command {
                print("    $ \(command)")
            }
        }
        print("\nChanges:")
        for release in manifest.changelog {
            print("  \(release.version) (\(release.date))")
            release.changes.forEach { print("    - \($0)") }
        }
    }
}
