import Foundation
import Testing
@testable import FactoryLogCore

@Test
func narratorWritesOncePerDayOfWorkAndReusesTheCache() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let engine = StubEngine(reply: "- \"Renamed the summary tab.\"")
    let cache = NarrativeCache(url: directory.appending(path: "narratives.json"))
    let summary = makeSummary()
    let narrator = DayNarrator(engine: engine, model: "stub", cache: cache)

    let first = await narrator.narrative(for: summary, on: summary.lastUpdatedAt)
    let second = await narrator.narrative(for: summary, on: summary.lastUpdatedAt)

    // Bullets and wrapping quotes are stripped from the model's reply.
    #expect(first == "Renamed the summary tab.")
    #expect(second == first)
    #expect(await engine.callCount == 1)

    // A fresh narrator reads the sentence back from disk instead of asking again.
    let reopened = DayNarrator(engine: engine, model: "stub", cache: cache)
    #expect(await reopened.cachedNarrative(for: summary, on: summary.lastUpdatedAt) == first)
    #expect(await engine.callCount == 1)
}

@Test
func narratorRewritesWhenTheDayGainsAnotherUpdate() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let engine = StubEngine(reply: "Shipped the tab.")
    let cache = NarrativeCache(url: directory.appending(path: "narratives.json"))
    let narrator = DayNarrator(engine: engine, model: "stub", cache: cache)

    let summary = makeSummary()
    _ = await narrator.narrative(for: summary, on: summary.lastUpdatedAt)

    let extended = makeSummary(extraEventID: "3")
    #expect(await narrator.cachedNarrative(for: extended, on: extended.lastUpdatedAt) == nil)

    _ = await narrator.narrative(for: extended, on: extended.lastUpdatedAt)
    #expect(await engine.callCount == 2)
}

@Test
func narratorStaysQuietWhenNoEngineIsRunning() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let engine = StubEngine(reply: "unused", available: false)
    let narrator = DayNarrator(
        engine: engine,
        model: "stub",
        cache: NarrativeCache(url: directory.appending(path: "narratives.json"))
    )
    let summary = makeSummary()

    #expect(await narrator.narrative(for: summary, on: summary.lastUpdatedAt) == nil)
    // The unreachable engine is not asked again on the next row.
    _ = await narrator.narrative(for: summary, on: summary.lastUpdatedAt)
    #expect(await engine.availabilityChecks == 1)
    #expect(await engine.callCount == 0)
}

@Test
func narratedSentencesNameTheWorkRatherThanADoer() {
    #expect(DayNarrator.tidy("The team shipped the summary tab.") == "Shipped the summary tab.")
    #expect(DayNarrator.tidy("We rewrote the log rows.") == "Rewrote the log rows.")
    #expect(DayNarrator.tidy("The project migrated ten playbooks.") == "Migrated ten playbooks.")
    // A sentence that already starts with the work is left alone.
    #expect(DayNarrator.tidy("Improved the icon.") == "Improved the icon.")
    // "In" only looks like the stripped "I " prefix.
    #expect(DayNarrator.tidy("Introduced a cache.") == "Introduced a cache.")
}

@Test
func sentencesWrittenUnderOlderWordingRulesAreReplaced() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let cache = NarrativeCache(url: directory.appending(path: "narratives.json"))
    let summary = makeSummary()
    let key = DayNarrator.key(for: summary, on: summary.lastUpdatedAt)
    cache.save([
        key: NarrativeCache.Entry(
            signature: summary.signature,
            model: "stub",
            text: "The team did some work.",
            promptVersion: nil
        )
    ])

    let engine = StubEngine(reply: "Rewrote the row.")
    let narrator = DayNarrator(engine: engine, model: "stub", cache: cache)

    #expect(await narrator.cachedNarrative(for: summary, on: summary.lastUpdatedAt) == nil)
    #expect(await narrator.narrative(for: summary, on: summary.lastUpdatedAt) == "Rewrote the row.")
}

@Test
func narrativesWrittenByAnotherModelAreReplaced() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = NarrativeCache(url: directory.appending(path: "narratives.json"))
    let summary = makeSummary()
    let key = DayNarrator.key(for: summary, on: summary.lastUpdatedAt)
    cache.save([
        key: NarrativeCache.Entry(
            signature: summary.signature,
            model: "old-model",
            text: "Old wording.",
            promptVersion: DayNarrator.promptVersion
        )
    ])

    let engine = StubEngine(reply: "Fresh wording.")
    let narrator = DayNarrator(engine: engine, model: "new-model", cache: cache)

    #expect(await narrator.cachedNarrative(for: summary, on: summary.lastUpdatedAt) == nil)
    #expect(await narrator.narrative(for: summary, on: summary.lastUpdatedAt) == "Fresh wording.")
    #expect(await engine.callCount == 1)
}

@Test
func promptCarriesTheDaysReportsForOneProject() {
    let summary = makeSummary()
    let prompt = DayNarrator.prompt(for: summary, on: summary.lastUpdatedAt)

    #expect(prompt.contains("Project: a"))
    #expect(prompt.contains("Task task_a: task.started task_a"))
    #expect(prompt.contains("Task task_a: task.reported task_a"))
    #expect(!prompt.contains("/projects/a"))
}

private actor StubEngine: NarrativeEngine {
    private let reply: String
    private let available: Bool
    private(set) var callCount = 0
    private(set) var availabilityChecks = 0

    init(reply: String, available: Bool = true) {
        self.reply = reply
        self.available = available
    }

    func isAvailable() async -> Bool {
        availabilityChecks += 1
        return available
    }

    func write(system: String, prompt: String) async throws -> String {
        callCount += 1
        return reply
    }
}

private func makeSummary(extraEventID: String? = nil) -> FactoryLogProjectSummary {
    let day = Date(timeIntervalSince1970: 1_785_053_460)
    let project = FactoryLogEvent.Project(name: "a", path: "/projects/a")

    var events = [
        makeEvent(id: "1", taskID: "task_a", kind: .started, path: project.path, timestamp: day),
        makeEvent(id: "2", taskID: "task_a", kind: .reported, path: project.path, timestamp: day.addingTimeInterval(60))
    ]
    if let extraEventID {
        events.append(
            makeEvent(
                id: extraEventID,
                taskID: "task_a",
                kind: .reported,
                path: project.path,
                timestamp: day.addingTimeInterval(120)
            )
        )
    }

    return FactoryLogProjectSummary(
        project: project,
        tasks: [FactoryLogTask(events: events)].compactMap { $0 },
        events: events
    )
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
