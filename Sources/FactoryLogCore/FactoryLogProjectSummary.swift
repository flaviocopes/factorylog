import Foundation

/// One project's work on a single day, rolled up from that day's events.
public struct FactoryLogProjectSummary: Identifiable, Equatable, Sendable {
    public var id: String {
        project.path
    }

    public let project: FactoryLogEvent.Project
    /// Tasks touched that day, most recently updated first.
    public let tasks: [FactoryLogTask]
    /// That day's updates for this project, oldest first.
    public let events: [FactoryLogEvent]

    public var updateCount: Int {
        events.count
    }

    public var lastUpdatedAt: Date {
        events.last?.timestamp ?? tasks.first?.lastUpdatedAt ?? .distantPast
    }

    public var doingCount: Int {
        tasks.count { $0.status == .doing }
    }

    public var doneCount: Int {
        tasks.count { $0.status == .done }
    }

    /// Changes whenever the day gains another update, so anything derived from
    /// this summary can be cached against it and regenerated only when stale.
    public var signature: String {
        "\(events.count):\(events.last?.id ?? "")"
    }

    public init(
        project: FactoryLogEvent.Project,
        tasks: [FactoryLogTask],
        events: [FactoryLogEvent]
    ) {
        self.project = project
        self.tasks = tasks
        self.events = events
    }
}
