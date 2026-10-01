import Foundation

/// Counts preserved after detailed events have been compacted from the live log.
/// Aggregates contain no implementation summaries, but retain enough information
/// for long-range activity charts and distinct-task counts.
public struct FactoryLogDailyAggregate: Codable, Equatable, Identifiable, Sendable {
    public let day: Date
    public let project: FactoryLogEvent.Project
    public let updateCount: Int
    public let taskIDs: [String]

    public init(
        day: Date,
        project: FactoryLogEvent.Project,
        updateCount: Int,
        taskIDs: [String]
    ) {
        self.day = day
        self.project = project
        self.updateCount = updateCount
        self.taskIDs = taskIDs.sorted()
    }

    public var id: String {
        "\(day.timeIntervalSinceReferenceDate)-\(project.path)"
    }
}
