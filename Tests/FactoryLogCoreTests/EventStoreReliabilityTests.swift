import Foundation
import Testing
@testable import FactoryLogCore

@Test
func concurrentWritersPreserveEveryEvent() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    try store.appendValidated(event(id: "start", taskID: "task", kind: .started))

    let reportCount = 300
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<reportCount {
            group.addTask {
                try store.appendValidated(
                    event(id: "report-\(index)", taskID: "task", kind: .reported)
                )
            }
        }
        try await group.waitForAll()
    }

    let events = try store.loadEvents()
    #expect(events.count == reportCount + 1)
    #expect(Set(events.map(\.id)).count == reportCount + 1)
}

@Test
func validatedAppendRejectsUpdatesAfterArchive() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    try store.appendValidated(event(id: "start", taskID: "task", kind: .started))
    try store.appendValidated(event(id: "archive", taskID: "task", kind: .archived))

    #expect(throws: EventStore.StoreError.taskAlreadyArchived("task")) {
        try store.appendValidated(event(id: "late", taskID: "task", kind: .reported))
    }
}

@Test
func staleTasksAreArchivedOnceAcrossConcurrentReloads() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try store.appendValidated(
        event(
            id: "stale-start",
            taskID: "stale",
            kind: .started,
            timestamp: now.addingTimeInterval(-EventStore.automaticArchiveInterval)
        )
    )
    try store.appendValidated(
        event(
            id: "recent-start",
            taskID: "recent",
            kind: .started,
            timestamp: now.addingTimeInterval(-EventStore.automaticArchiveInterval + 1)
        )
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<50 {
            group.addTask {
                try store.archiveStaleTasks(now: now)
            }
        }
        try await group.waitForAll()
    }

    let events = try store.loadEvents()
    let staleEvents = events.filter { $0.taskID == "stale" }
    #expect(staleEvents.map(\.kind) == [.started, .archived])
    #expect(staleEvents.last?.timestamp == now)
    #expect(staleEvents.last?.summary == "Automatically marked Done 24 hours after the task started.")
    #expect(events.filter { $0.taskID == "recent" }.map(\.kind) == [.started])
}

@Test
func loadSnapshotKeepsReadableEventsAndReportsBadRecords() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    try store.append(event(id: "valid", taskID: "task", kind: .started))
    try store.append(
        FactoryLogEvent(
            schemaVersion: 99,
            id: "future",
            taskID: "future-task",
            kind: .started,
            project: .init(name: "Project", path: "/tmp/project"),
            taskTitle: "Task",
            source: .init(tool: .other),
            summary: "Summary"
        )
    )
    let handle = try FileHandle(forWritingTo: store.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("not-json\n".utf8))
    try handle.close()

    let snapshot = try store.loadSnapshot()
    #expect(snapshot.events.map(\.id) == ["valid"])
    #expect(snapshot.issues == [
        .init(line: 2, kind: .unsupportedSchemaVersion(99)),
        .init(line: 3, kind: .invalidEvent)
    ])
}

@Test
func unknownSourceIdentifiersRoundTrip() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    let custom = FactoryLogEvent(
        id: "custom-source",
        taskID: "task",
        kind: .started,
        project: .init(name: "Project", path: "/tmp/project"),
        taskTitle: "Task",
        source: .init(tool: .init(rawValue: "windsurf")),
        summary: "Summary"
    )
    try store.append(custom)

    #expect(try store.loadEvents().first?.source.tool.rawValue == "windsurf")
}

@Test
func watcherReportsTheFirstEventWhenTheDirectoryIsCreatedLazily() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = EventStore(url: root.appending(path: "nested/events.jsonl"))
    let changes = EventStoreWatcher(
        url: store.url,
        debounce: 0.01,
        directoryRetry: 0.02
    ).changes()
    let observation = Task {
        for await _ in changes { return true }
        return false
    }

    try await Task.sleep(for: .milliseconds(10))
    try store.append(event(id: "first", taskID: "task", kind: .started))

    let deadline = Task {
        try await Task.sleep(for: .seconds(2))
        observation.cancel()
    }
    let changed = await observation.value
    deadline.cancel()

    #expect(changed)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
}

private func event(
    id: String,
    taskID: String,
    kind: FactoryLogEvent.Kind,
    timestamp: Date = Date()
) -> FactoryLogEvent {
    FactoryLogEvent(
        id: id,
        taskID: taskID,
        timestamp: timestamp,
        kind: kind,
        project: .init(name: "Project", path: "/tmp/project"),
        taskTitle: "Task",
        source: .init(tool: .codex, sessionID: "session"),
        summary: id
    )
}
