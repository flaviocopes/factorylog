import Foundation
import Testing
@testable import FactoryLogCore

@Test
func storeQueriesDoingDoneDailyAndProjectHistory() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let selectedDay = Date(timeIntervalSince1970: 1_785_053_460)
    let dayStart = calendar.startOfDay(for: selectedDay)
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))

    let events = [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: dayStart.addingTimeInterval(60)),
        makeEvent(id: "2", taskID: "task_b", kind: .started, path: "/projects/b", timestamp: dayStart.addingTimeInterval(120)),
        makeEvent(id: "3", taskID: "task_a", kind: .reported, path: "/projects/a", timestamp: dayStart.addingTimeInterval(180)),
        makeEvent(id: "4", taskID: "task_a", kind: .archived, path: "/projects/a", timestamp: nextDay.addingTimeInterval(60)),
        makeEvent(id: "5", taskID: "task_b", kind: .reported, path: "/projects/b", timestamp: nextDay.addingTimeInterval(120))
    ]

    let store = EventStore(url: temporaryDirectory.appending(path: "events.jsonl"))
    for event in events {
        try store.append(event)
    }

    #expect(try store.doingTasks().map(\.taskID) == ["task_b"])
    #expect(try store.doneTasks().map(\.taskID) == ["task_a"])
    #expect(try store.activity(on: selectedDay, calendar: calendar).map(\.id) == ["1", "2", "3"])
    #expect(try store.projectHistory(path: "/projects/a").map(\.id) == ["1", "3", "4"])
}

@Test
func tasksActiveOnADayAppearOnceMostRecentlyUpdatedFirst() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let selectedDay = Date(timeIntervalSince1970: 1_785_053_460)
    let dayStart = calendar.startOfDay(for: selectedDay)
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))

    let history = FactoryLogHistory(events: [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: dayStart.addingTimeInterval(60)),
        makeEvent(id: "2", taskID: "task_b", kind: .started, path: "/projects/b", timestamp: dayStart.addingTimeInterval(120)),
        makeEvent(id: "3", taskID: "task_a", kind: .reported, path: "/projects/a", timestamp: dayStart.addingTimeInterval(180)),
        makeEvent(id: "4", taskID: "task_a", kind: .archived, path: "/projects/a", timestamp: nextDay.addingTimeInterval(60))
    ])

    let tasks = history.tasks(activeOn: selectedDay, calendar: calendar)

    // task_a received three updates but is listed once, ahead of task_b because
    // its last update that day is later.
    #expect(tasks.map(\.taskID) == ["task_a", "task_b"])

    let taskA = try #require(tasks.first)
    // Status covers the whole thread, including the next day's archive.
    #expect(taskA.status == .done)
    #expect(taskA.events(on: selectedDay, calendar: calendar).map(\.id) == ["1", "3"])

    #expect(history.tasks(activeOn: nextDay, calendar: calendar).map(\.taskID) == ["task_a"])
}

@Test
func anAutomaticArchiveDoesNotMakeATaskActiveThatDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_053_460))
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))

    let history = FactoryLogHistory(events: [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: dayStart.addingTimeInterval(60)),
        FactoryLogEvent(
            id: "2",
            taskID: "task_a",
            timestamp: nextDay.addingTimeInterval(120),
            kind: .archived,
            project: .init(name: "a", path: "/projects/a"),
            taskTitle: "Task task_a",
            source: .init(tool: .cursor),
            summary: EventStore.automaticArchiveSummary
        )
    ])

    #expect(history.tasks(activeOn: nextDay, calendar: calendar).isEmpty)
    #expect(history.projectSummaries(on: nextDay, calendar: calendar).isEmpty)
    // The archive still closes the task on the day it started.
    #expect(history.tasks(activeOn: dayStart, calendar: calendar).first?.status == .done)
}

@Test
func tasksActiveInARangeKeepTheirWholeThread() throws {
    let start = Date(timeIntervalSince1970: 1_785_053_460)

    let history = FactoryLogHistory(events: [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: start),
        makeEvent(id: "2", taskID: "task_b", kind: .started, path: "/projects/a", timestamp: start.addingTimeInterval(60)),
        makeEvent(id: "3", taskID: "task_a", kind: .archived, path: "/projects/a", timestamp: start.addingTimeInterval(7_200))
    ])

    let tasks = history.tasks(activeIn: DateInterval(start: start.addingTimeInterval(3_600), duration: 7_200))

    // Only task_a was touched in the range, but its start before the range still counts.
    #expect(tasks.map(\.taskID) == ["task_a"])
    #expect(tasks.first?.events.map(\.id) == ["1", "3"])
    #expect(tasks.first?.status == .done)
}

@Test
func projectSummariesRollUpADayPerProject() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let selectedDay = Date(timeIntervalSince1970: 1_785_053_460)
    let dayStart = calendar.startOfDay(for: selectedDay)

    let history = FactoryLogHistory(events: [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: dayStart.addingTimeInterval(60)),
        makeEvent(id: "2", taskID: "task_b", kind: .started, path: "/projects/b", timestamp: dayStart.addingTimeInterval(120)),
        makeEvent(id: "3", taskID: "task_a", kind: .reported, path: "/projects/a", timestamp: dayStart.addingTimeInterval(180)),
        makeEvent(id: "4", taskID: "task_a", kind: .archived, path: "/projects/a", timestamp: dayStart.addingTimeInterval(240)),
        makeEvent(id: "5", taskID: "task_c", kind: .started, path: "/projects/a", timestamp: dayStart.addingTimeInterval(300))
    ])

    let summaries = history.projectSummaries(on: selectedDay, calendar: calendar)

    // Project a was touched last, so it leads.
    #expect(summaries.map(\.project.path) == ["/projects/a", "/projects/b"])

    let projectA = try #require(summaries.first)
    #expect(projectA.tasks.map(\.taskID) == ["task_c", "task_a"])
    #expect(projectA.updateCount == 4)
    #expect(projectA.doingCount == 1)
    #expect(projectA.doneCount == 1)
    #expect(projectA.lastUpdatedAt == dayStart.addingTimeInterval(300))
}

@Test
func watcherReportsEventsAppendedByAnotherProcess() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let store = EventStore(url: directory.appending(path: "events.jsonl"))
    try store.append(makeEvent(id: "1", taskID: "task_a", kind: .started, path: "/projects/a", timestamp: Date()))

    let changes = EventStoreWatcher(url: store.url, debounce: 0.01).changes()
    let observation = Task {
        for await _ in changes {
            return true
        }
        return false
    }

    // Give the watcher time to attach before writing.
    try await Task.sleep(for: .milliseconds(300))
    try store.append(makeEvent(id: "2", taskID: "task_a", kind: .reported, path: "/projects/a", timestamp: Date()))

    // Cancelling ends the stream, so a missed change fails instead of hanging.
    let deadline = Task {
        try await Task.sleep(for: .seconds(5))
        observation.cancel()
    }
    let reportedChange = await observation.value
    deadline.cancel()

    #expect(reportedChange)
    #expect(try store.loadEvents().map(\.id) == ["1", "2"])
}

private func makeEvent(
    id: String,
    taskID: String,
    kind: FactoryLogEvent.Kind,
    path: String,
    timestamp: Date
) -> FactoryLogEvent {
    FactoryLogEvent(
        id: id,
        taskID: taskID,
        timestamp: timestamp,
        kind: kind,
        project: .init(name: URL(fileURLWithPath: path).lastPathComponent, path: path),
        taskTitle: "Task \(taskID)",
        source: .init(tool: .cursor),
        summary: "\(kind.rawValue) \(taskID)"
    )
}
