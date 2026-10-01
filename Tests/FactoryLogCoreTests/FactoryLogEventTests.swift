import Foundation
import Testing
@testable import FactoryLogCore

@Test
func eventRoundTripsThroughJSON() throws {
    let event = makeEvent()

    let encoded = try FactoryLogJSON.makeEncoder().encode(event)
    let decoded = try FactoryLogJSON.makeDecoder().decode(FactoryLogEvent.self, from: encoded)
    let json = try #require(String(data: encoded, encoding: .utf8))

    #expect(decoded == event)
    #expect(json.contains(#""timestamp":"2026-07-26T08:11:00Z""#))
}

@Test
func eventStoreAppendsAndLoadsEvents() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let store = EventStore(url: temporaryDirectory.appending(path: "events.jsonl"))
    let event = makeEvent()

    try store.append(event)

    #expect(try store.loadEvents() == [event])
}

@Test
func eventStoreIgnoresAnIncompleteFinalLine() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let store = EventStore(url: temporaryDirectory.appending(path: "events.jsonl"))
    let event = makeEvent()
    try store.append(event)

    let handle = try FileHandle(forWritingTo: store.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"schemaVersion":1"#.utf8))
    try handle.close()

    #expect(try store.loadEvents() == [event])
}

private func makeEvent() -> FactoryLogEvent {
    FactoryLogEvent(
        taskID: "task_factorylog",
        timestamp: Date(timeIntervalSince1970: 1_785_053_460),
        kind: .reported,
        project: .init(name: "Factory Log", path: "/tmp/factorylog"),
        taskTitle: "Build the prototype",
        source: .init(tool: .cursor, sessionID: "session_123"),
        summary: "Defined the event model."
    )
}
