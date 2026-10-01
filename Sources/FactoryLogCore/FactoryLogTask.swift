import Foundation

public struct FactoryLogTask: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case doing
        case done
    }

    public var id: String {
        taskID
    }

    public let taskID: String
    public let project: FactoryLogEvent.Project
    public let title: String
    public let status: Status
    public let events: [FactoryLogEvent]

    public var startedAt: Date {
        events[0].timestamp
    }

    public var lastUpdatedAt: Date {
        events[events.count - 1].timestamp
    }

    /// A launchable link back to the originating Codex task, when the task is
    /// still active and its start event recorded a real Codex thread UUID.
    public var codexThreadURL: URL? {
        guard status == .doing,
              let source = events.first(where: { $0.kind == .started })?.source,
              source.tool == .codex,
              let sessionID = source.sessionID,
              UUID(uuidString: sessionID) != nil else {
            return nil
        }

        return URL(string: "codex://threads/\(sessionID)")
    }

    /// This task's updates that happened on `day`, oldest first.
    public func events(on day: Date, calendar: Calendar = .current) -> [FactoryLogEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            return []
        }
        return events.filter { interval.contains($0.timestamp) }
    }

    init?(events: [FactoryLogEvent]) {
        let orderedEvents = events.chronological()
        guard let started = orderedEvents.first(where: { $0.kind == .started }) else {
            return nil
        }

        taskID = started.taskID
        project = started.project
        title = started.taskTitle
        status = orderedEvents.contains(where: { $0.kind == .archived }) ? .done : .doing
        self.events = orderedEvents
    }
}

extension Array where Element == FactoryLogEvent {
    func chronological() -> [FactoryLogEvent] {
        enumerated()
            .sorted { left, right in
                if left.element.timestamp == right.element.timestamp {
                    return left.offset < right.offset
                }
                return left.element.timestamp < right.element.timestamp
            }
            .map(\.element)
    }
}
