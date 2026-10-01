import Foundation
import Testing
@testable import FactoryLogCore

private let start = Date(timeIntervalSince1970: 1_785_053_460)
private let leadIn = FactoryLogActiveTime.sessionLeadIn

@Test
func updatesWithinTheSessionGapCountAsContinuousWork() {
    let events = [
        makeEvent(id: "1", path: "/projects/a", minutes: 0),
        makeEvent(id: "2", path: "/projects/a", minutes: 20),
        makeEvent(id: "3", path: "/projects/a", minutes: 65)
    ]

    let activeTime = FactoryLogActiveTime(events: events)

    #expect(activeTime.seconds(for: events[0]) == leadIn)
    #expect(activeTime.seconds(for: events[1]) == 20 * 60)
    #expect(activeTime.seconds(for: events[2]) == 45 * 60)
    #expect(activeTime.seconds(for: events) == leadIn + 65 * 60)
}

@Test
func aLongPauseStartsANewSession() {
    let events = [
        makeEvent(id: "1", path: "/projects/a", minutes: 0),
        makeEvent(id: "2", path: "/projects/a", minutes: 10),
        makeEvent(id: "3", path: "/projects/a", minutes: 120)
    ]

    let activeTime = FactoryLogActiveTime(events: events)

    #expect(activeTime.seconds(for: events[2]) == leadIn)
    #expect(activeTime.seconds(for: events) == leadIn + 10 * 60 + leadIn)
}

@Test
func projectsAreMeasuredIndependently() {
    let events = [
        makeEvent(id: "1", path: "/projects/a", minutes: 0),
        makeEvent(id: "2", path: "/projects/b", minutes: 5),
        makeEvent(id: "3", path: "/projects/a", minutes: 30)
    ]

    let activeTime = FactoryLogActiveTime(events: events)

    // Project b's update in between neither splits nor shortens project a's session.
    #expect(activeTime.seconds(for: events.filter { $0.project.path == "/projects/a" }) == leadIn + 30 * 60)
    #expect(activeTime.seconds(for: events[1]) == leadIn)
}

@Test
func automaticArchivesRecordNoWork() {
    let events = [
        makeEvent(id: "1", path: "/projects/a", minutes: 0),
        makeEvent(id: "2", path: "/projects/a", minutes: 30, summary: EventStore.automaticArchiveSummary),
        makeEvent(id: "3", path: "/projects/a", minutes: 60)
    ]

    let activeTime = FactoryLogActiveTime(events: events)

    #expect(events[1].isAutomaticArchive)
    #expect(activeTime.seconds(for: events[1]) == 0)
    // Without the archive bridging it, the 60-minute pause starts a new session.
    #expect(activeTime.seconds(for: events[2]) == leadIn)
}

@Test
func sessionsSpanTheTimeTheyCredit() {
    let events = [
        makeEvent(id: "1", path: "/projects/a", minutes: 0),
        makeEvent(id: "2", path: "/projects/a", minutes: 30),
        makeEvent(id: "3", path: "/projects/b", minutes: 40),
        makeEvent(id: "4", path: "/projects/a", minutes: 200),
        makeEvent(id: "5", path: "/projects/a", minutes: 210, summary: EventStore.automaticArchiveSummary)
    ]

    let activeTime = FactoryLogActiveTime(events: events)
    let sessions = activeTime.sessions

    #expect(sessions.map(\.project.path) == ["/projects/a", "/projects/b", "/projects/a"])
    #expect(sessions[0].start == start.addingTimeInterval(-leadIn))
    #expect(sessions[0].end == start.addingTimeInterval(30 * 60))
    #expect(sessions[0].events.map(\.id) == ["1", "2"])
    // The automatic archive neither joins nor extends the last session.
    #expect(sessions[2].events.map(\.id) == ["4"])
    #expect(sessions.reduce(0) { $0 + $1.duration } == activeTime.seconds(for: events))

    let afternoon = DateInterval(start: start.addingTimeInterval(190 * 60), duration: 3_600)
    #expect(activeTime.sessions(overlapping: afternoon).map(\.events.first?.id) == ["4"])
}

private func makeEvent(
    id: String,
    path: String,
    minutes: Double,
    summary: String = "Shipped a change."
) -> FactoryLogEvent {
    FactoryLogEvent(
        id: id,
        taskID: "task_\(id)",
        timestamp: start.addingTimeInterval(minutes * 60),
        kind: summary == EventStore.automaticArchiveSummary ? .archived : .reported,
        project: .init(name: URL(fileURLWithPath: path).lastPathComponent, path: path),
        taskTitle: "Task \(id)",
        source: .init(tool: .cursor),
        summary: summary
    )
}
