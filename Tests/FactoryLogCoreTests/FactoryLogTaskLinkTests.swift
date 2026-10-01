import Foundation
import Testing
@testable import FactoryLogCore

@Test
func doingCodexTaskLinksToItsRecordedThread() throws {
    let threadID = "019faf85-5fe6-7863-bc97-42f3a08e85df"
    let task = try #require(makeTask(source: .init(tool: .codex, sessionID: threadID)))

    #expect(task.codexThreadURL?.absoluteString == "codex://threads/\(threadID)")
}

@Test
func completedCodexTaskDoesNotExposeAThreadLink() throws {
    let source = FactoryLogEvent.Source(
        tool: .codex,
        sessionID: "019faf85-5fe6-7863-bc97-42f3a08e85df"
    )
    let task = try #require(makeTask(source: source, isArchived: true))

    #expect(task.codexThreadURL == nil)
}

@Test(arguments: [
    FactoryLogEvent.Source(tool: .codex),
    FactoryLogEvent.Source(tool: .codex, sessionID: "imported-work-log"),
    FactoryLogEvent.Source(tool: .cursor, sessionID: "019faf85-5fe6-7863-bc97-42f3a08e85df")
])
func taskWithoutARealCodexThreadDoesNotExposeALink(source: FactoryLogEvent.Source) throws {
    let task = try #require(makeTask(source: source))

    #expect(task.codexThreadURL == nil)
}

private func makeTask(
    source: FactoryLogEvent.Source,
    isArchived: Bool = false
) -> FactoryLogTask? {
    let started = FactoryLogEvent(
        taskID: "task_linked",
        timestamp: Date(timeIntervalSince1970: 1_785_053_460),
        kind: .started,
        project: .init(name: "Factory Log", path: "/tmp/factorylog"),
        taskTitle: "Open a task in Codex",
        source: source,
        summary: "Started linking tasks."
    )
    var events = [started]

    if isArchived {
        events.append(
            FactoryLogEvent(
                taskID: started.taskID,
                timestamp: started.timestamp.addingTimeInterval(60),
                kind: .archived,
                project: started.project,
                taskTitle: started.taskTitle,
                source: source,
                summary: "Finished linking tasks."
            )
        )
    }

    return FactoryLogTask(events: events)
}
