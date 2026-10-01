import Foundation

/// Hands-on time estimated from when updates arrived, since agents report
/// outcomes rather than clock time.
///
/// Within one project, updates at most `sessionGap` apart form one session, and
/// each update is credited the time since the previous one. The first update of
/// a session is credited `sessionLeadIn` for the work before it. Automatic
/// archives earn nothing and never extend a session. Each project is measured
/// on its own, so parallel work in two projects counts toward both.
public struct FactoryLogActiveTime: Sendable {
    public static let sessionGap: TimeInterval = 45 * 60
    public static let sessionLeadIn: TimeInterval = 5 * 60

    /// Every session across all projects, earliest first.
    public let sessions: [FactoryLogWorkSession]
    private let secondsByEventID: [String: TimeInterval]

    public init(events: [FactoryLogEvent]) {
        var secondsByEventID: [String: TimeInterval] = [:]
        var sessions: [FactoryLogWorkSession] = []
        let workEvents = events.filter { !$0.isAutomaticArchive }

        for projectEvents in Dictionary(grouping: workEvents, by: \.project.path).values {
            var current: [FactoryLogEvent] = []
            for event in projectEvents.chronological() {
                let credit: TimeInterval
                if let previous = current.last?.timestamp,
                   event.timestamp.timeIntervalSince(previous) <= Self.sessionGap {
                    credit = event.timestamp.timeIntervalSince(previous)
                } else {
                    credit = Self.sessionLeadIn
                    if !current.isEmpty {
                        sessions.append(FactoryLogWorkSession(events: current))
                    }
                    current = []
                }
                secondsByEventID[event.id, default: 0] += credit
                current.append(event)
            }
            if !current.isEmpty {
                sessions.append(FactoryLogWorkSession(events: current))
            }
        }

        self.sessions = sessions.sorted { $0.start < $1.start }
        self.secondsByEventID = secondsByEventID
    }

    public func seconds(for event: FactoryLogEvent) -> TimeInterval {
        secondsByEventID[event.id] ?? 0
    }

    public func seconds(for events: some Sequence<FactoryLogEvent>) -> TimeInterval {
        events.reduce(0) { $0 + seconds(for: $1) }
    }

    public func sessions(overlapping interval: DateInterval) -> [FactoryLogWorkSession] {
        sessions.filter { $0.end > interval.start && $0.start < interval.end }
    }
}

/// A stretch of continuous work on one project, from the lead-in before its
/// first update to its last update.
public struct FactoryLogWorkSession: Identifiable, Equatable, Sendable {
    public let project: FactoryLogEvent.Project
    public let start: Date
    public let end: Date
    /// The session's updates, oldest first.
    public let events: [FactoryLogEvent]

    public var id: String {
        "\(project.path)|\(start.timeIntervalSinceReferenceDate)"
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    init(events: [FactoryLogEvent]) {
        project = events[0].project
        start = events[0].timestamp.addingTimeInterval(-FactoryLogActiveTime.sessionLeadIn)
        end = events[events.count - 1].timestamp
        self.events = events
    }
}
