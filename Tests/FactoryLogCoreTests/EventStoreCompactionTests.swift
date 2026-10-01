import Foundation
import Testing
@testable import FactoryLogCore

@Test
func compactionRequiresAtLeastThirtyDays() throws {
    let directory = compactionTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = EventStore(url: directory.appending(path: "events.jsonl"))

    #expect(throws: EventStore.StoreError.retentionTooShort(29)) {
        try store.compactionPreview(retainingDays: 29)
    }
    #expect(throws: EventStore.StoreError.retentionTooShort(7)) {
        try store.compact(retainingDays: 7)
    }
}

@Test
func compactionPreservesActivityAndEssentialTaskHistory() throws {
    let directory = compactionTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))

    let oldStart = compactedEvent(id: "done-start", taskID: "done", kind: .started, daysAgo: 70, now: now)
    let oldReportOne = compactedEvent(id: "done-report-1", taskID: "done", kind: .reported, daysAgo: 60, now: now)
    let oldReportTwo = compactedEvent(id: "done-report-2", taskID: "done", kind: .reported, daysAgo: 50, now: now)
    let oldArchive = compactedEvent(id: "done-archive", taskID: "done", kind: .archived, daysAgo: 40, now: now)
    let openStart = compactedEvent(id: "open-start", taskID: "open", kind: .started, daysAgo: 80, now: now)
    let openReport = compactedEvent(id: "open-report", taskID: "open", kind: .reported, daysAgo: 45, now: now)
    let recentStart = compactedEvent(id: "recent-start", taskID: "recent", kind: .started, daysAgo: 10, now: now)
    let original = [oldStart, oldReportOne, oldReportTwo, oldArchive, openStart, openReport, recentStart]
    for event in original {
        try store.append(event)
    }

    let preview = try store.compactionPreview(retainingDays: 30, now: now, calendar: utcCalendar())
    #expect(preview.removableEventCount == 2)
    #expect(preview.protectedEventCount == 4)

    let result = try store.compact(retainingDays: 30, now: now, calendar: utcCalendar())
    #expect(result.removedEventCount == 2)
    #expect(result.retainedEventCount == 5)

    let snapshot = try store.loadSnapshot()
    #expect(Set(snapshot.events.map(\.id)) == ["done-start", "done-archive", "open-start", "open-report", "recent-start"])
    #expect(snapshot.dailyAggregates.reduce(0) { $0 + $1.updateCount } == 2)
    #expect(Set(snapshot.dailyAggregates.flatMap(\.taskIDs)) == ["done"])

    let preservedCount = snapshot.events.count + snapshot.dailyAggregates.reduce(0) { $0 + $1.updateCount }
    #expect(preservedCount == original.count)

    try store.appendValidated(
        compactedEvent(id: "open-after-purge", taskID: "open", kind: .reported, daysAgo: 0, now: now)
    )
    #expect(throws: EventStore.StoreError.taskAlreadyArchived("done")) {
        try store.appendValidated(
            compactedEvent(id: "done-after-purge", taskID: "done", kind: .reported, daysAgo: 0, now: now)
        )
    }

    let secondResult = try store.compact(retainingDays: 30, now: now, calendar: utcCalendar())
    #expect(secondResult.removedEventCount == 0)
    #expect(try store.loadSnapshot().dailyAggregates == snapshot.dailyAggregates)

    let usage = try store.storageUsage()
    #expect(usage.detailedEventCount == 6)
    #expect(usage.aggregateCount == 2)
    #expect(usage.detailedBytes > 0)
    #expect(usage.aggregateBytes > 0)
}

private func compactionTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
}

private func compactedEvent(
    id: String,
    taskID: String,
    kind: FactoryLogEvent.Kind,
    daysAgo: Int,
    now: Date
) -> FactoryLogEvent {
    let timestamp = utcCalendar().date(byAdding: .day, value: -daysAgo, to: now) ?? now
    return FactoryLogEvent(
        id: id,
        taskID: taskID,
        timestamp: timestamp,
        kind: kind,
        project: .init(name: "Project", path: "/tmp/project"),
        taskTitle: taskID,
        source: .init(tool: .codex, sessionID: "session"),
        summary: id
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}
