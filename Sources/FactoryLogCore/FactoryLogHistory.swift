import Foundation

public struct FactoryLogHistory: Sendable {
    public let events: [FactoryLogEvent]

    public init(events: [FactoryLogEvent]) {
        self.events = events.chronological()
    }

    public func doingTasks() -> [FactoryLogTask] {
        tasks(status: .doing)
    }

    public func doneTasks() -> [FactoryLogTask] {
        tasks(status: .done)
    }

    public func activity(on day: Date, calendar: Calendar = .current) -> [FactoryLogEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            return []
        }
        return events.filter { interval.contains($0.timestamp) }
    }

    public func projectHistory(path: String) -> [FactoryLogEvent] {
        events.filter { $0.project.path == path }
    }

    /// Every task touched on `day`, most recently updated first.
    ///
    /// A task appears once no matter how many updates it received that day. Each
    /// task carries its whole thread, so status reflects history beyond `day`.
    public func tasks(activeOn day: Date, calendar: Calendar = .current) -> [FactoryLogTask] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            return []
        }
        return tasks(activeIn: interval)
    }

    /// Every task touched during `interval`, most recently updated first, each
    /// carrying its whole thread. An automatic archive closes a task without
    /// touching it, so it doesn't count.
    public func tasks(activeIn interval: DateInterval) -> [FactoryLogTask] {
        var lastUpdateInInterval: [String: Date] = [:]
        for event in events where interval.contains(event.timestamp) && !event.isAutomaticArchive {
            lastUpdateInInterval[event.taskID] = event.timestamp
        }

        return allTasks()
            .compactMap { task in
                lastUpdateInInterval[task.taskID].map { (task: task, updatedAt: $0) }
            }
            .sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.task.taskID < right.task.taskID
                }
                return left.updatedAt > right.updatedAt
            }
            .map(\.task)
    }

    /// The day's work rolled up per project, most recently active project first.
    public func projectSummaries(on day: Date, calendar: Calendar = .current) -> [FactoryLogProjectSummary] {
        let dayEvents = Dictionary(
            grouping: activity(on: day, calendar: calendar).filter { !$0.isAutomaticArchive },
            by: \.project.path
        )

        return Dictionary(grouping: tasks(activeOn: day, calendar: calendar), by: \.project.path)
            .values
            .compactMap { tasks -> FactoryLogProjectSummary? in
                guard let project = tasks.first?.project, let events = dayEvents[project.path] else {
                    return nil
                }
                return FactoryLogProjectSummary(project: project, tasks: tasks, events: events)
            }
            .sorted { left, right in
                if left.lastUpdatedAt == right.lastUpdatedAt {
                    return left.project.name.localizedCaseInsensitiveCompare(right.project.name) == .orderedAscending
                }
                return left.lastUpdatedAt > right.lastUpdatedAt
            }
    }

    private func allTasks() -> [FactoryLogTask] {
        Dictionary(grouping: events, by: \.taskID)
            .values
            .compactMap(FactoryLogTask.init(events:))
    }

    private func tasks(status: FactoryLogTask.Status) -> [FactoryLogTask] {
        allTasks()
            .filter { $0.status == status }
            .sorted { left, right in
                if left.lastUpdatedAt == right.lastUpdatedAt {
                    return left.taskID < right.taskID
                }
                return left.lastUpdatedAt > right.lastUpdatedAt
            }
    }
}

public extension EventStore {
    func doingTasks() throws -> [FactoryLogTask] {
        try FactoryLogHistory(events: loadEvents()).doingTasks()
    }

    func doneTasks() throws -> [FactoryLogTask] {
        try FactoryLogHistory(events: loadEvents()).doneTasks()
    }

    func tasks(activeOn day: Date, calendar: Calendar = .current) throws -> [FactoryLogTask] {
        try FactoryLogHistory(events: loadEvents()).tasks(activeOn: day, calendar: calendar)
    }

    func activity(on day: Date, calendar: Calendar = .current) throws -> [FactoryLogEvent] {
        try FactoryLogHistory(events: loadEvents()).activity(on: day, calendar: calendar)
    }

    func projectHistory(path: String) throws -> [FactoryLogEvent] {
        try FactoryLogHistory(events: loadEvents()).projectHistory(path: path)
    }

    func projectSummaries(on day: Date, calendar: Calendar = .current) throws -> [FactoryLogProjectSummary] {
        try FactoryLogHistory(events: loadEvents()).projectSummaries(on: day, calendar: calendar)
    }
}
