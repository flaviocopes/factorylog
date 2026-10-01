import Foundation
import SwiftUI
import FactoryLogCore

struct DashboardSnapshot {
    let events: [FactoryLogEvent]
    let dailyAggregates: [FactoryLogDailyAggregate]
    let selectedProjectPath: String?
    let calendar: Calendar
    let today: Date
    let rangeStart: Date
    let rangeEnd: Date
    let heatmapStart: Date
    let heatmapEnd: Date

    init(
        events: [FactoryLogEvent],
        dailyAggregates: [FactoryLogDailyAggregate] = [],
        selectedProjectPath: String?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.events = events
        self.dailyAggregates = dailyAggregates
        self.selectedProjectPath = selectedProjectPath
        self.calendar = calendar

        let today = calendar.startOfDay(for: now)
        self.today = today
        self.rangeStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        self.rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        self.heatmapStart = calendar.date(byAdding: .weekOfYear, value: -11, to: currentWeek) ?? currentWeek
        self.heatmapEnd = calendar.date(byAdding: .day, value: 84, to: heatmapStart) ?? today
    }

    var rangeEvents: [FactoryLogEvent] {
        events.filter { $0.timestamp >= rangeStart && $0.timestamp < rangeEnd }
    }

    var visibleRangeEvents: [FactoryLogEvent] {
        filter(rangeEvents)
    }

    var heatmapEvents: [FactoryLogEvent] {
        filter(events.filter { $0.timestamp >= heatmapStart && $0.timestamp < heatmapEnd })
    }

    var previousRangeEvents: [FactoryLogEvent] {
        guard let previousStart = calendar.date(byAdding: .day, value: -30, to: rangeStart) else {
            return []
        }
        return filter(events.filter { $0.timestamp >= previousStart && $0.timestamp < rangeStart })
    }

    var projects: [DashboardProject] {
        Dictionary(grouping: rangeEvents, by: \.project.path)
            .values
            .compactMap { projectEvents in
                guard let project = projectEvents.first?.project,
                      let latest = projectEvents.max(by: { $0.timestamp < $1.timestamp }) else {
                    return nil
                }

                return DashboardProject(
                    project: project,
                    updateCount: projectEvents.count,
                    taskCount: Set(projectEvents.map(\.taskID)).count,
                    latestEvent: latest,
                    color: Self.color(for: project.path)
                )
            }
            .sorted {
                if $0.updateCount != $1.updateCount {
                    return $0.updateCount > $1.updateCount
                }
                return $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
            }
    }

    /// Looked up across all events, since the time card can pick a project that
    /// was quiet in the last 30 days.
    var selectedProject: FactoryLogEvent.Project? {
        guard let selectedProjectPath else {
            return nil
        }
        return events.last { $0.project.path == selectedProjectPath }?.project
    }

    var updateCount: Int {
        visibleRangeEvents.count
    }

    var taskCount: Int {
        Set(visibleRangeEvents.map(\.taskID)).count
    }

    var activeDayCount: Int {
        Set(visibleRangeEvents.map { calendar.startOfDay(for: $0.timestamp) }).count
    }

    var changePercentage: Int? {
        let previous = previousRangeEvents.count
        guard previous > 0 else {
            return nil
        }
        return Int(((Double(updateCount - previous) / Double(previous)) * 100).rounded())
    }

    var dailyActivity: [DashboardDay] {
        daySeries(from: rangeStart, count: 30, events: visibleRangeEvents)
    }

    var heatmapDays: [DashboardDay] {
        daySeries(from: heatmapStart, count: 84, events: heatmapEvents)
    }

    func activityDays(forWeeks weekCount: Int) -> [DashboardDay] {
        let weeks = max(weekCount, 1)
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeek) ?? currentWeek
        let end = calendar.date(byAdding: .day, value: weeks * 7, to: start) ?? rangeEnd

        return daySeries(from: start, count: weeks * 7, counts: dayCounts(from: start, to: end))
    }

    var longestActiveStreak: Int {
        var longest = 0
        var current = 0

        for day in activityDays(forWeeks: 26) where !day.isFuture {
            if day.count > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return longest
    }

    var stackPoints: [DashboardStackPoint] {
        let grouped = Dictionary(grouping: visibleRangeEvents) { event in
            DashboardActivityKey(
                day: calendar.startOfDay(for: event.timestamp),
                projectPath: event.project.path
            )
        }

        let days = Set(grouped.keys.map(\.day)).sorted()
        var points: [DashboardStackPoint] = []

        for day in days {
            var stackStart = 0
            for project in projects {
                let key = DashboardActivityKey(day: day, projectPath: project.project.path)
                guard let projectEvents = grouped[key] else {
                    continue
                }

                let count = projectEvents.count
                points.append(
                    DashboardStackPoint(
                        day: day,
                        projectPath: project.project.path,
                        projectName: project.project.name,
                        count: count,
                        stackStart: stackStart,
                        stackEnd: stackStart + count
                    )
                )
                stackStart += count
            }
        }

        return points
    }

    var recentTaskEvents: [FactoryLogEvent] {
        Dictionary(grouping: visibleRangeEvents, by: \.taskID)
            .values
            .compactMap { $0.max(by: { $0.timestamp < $1.timestamp }) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var recentOutcomes: [FactoryLogEvent] {
        latestTaskEvents.filter { $0.kind == .archived }
    }

    var openWork: [FactoryLogEvent] {
        latestTaskEvents.filter { $0.kind != .archived }
    }

    var projectPaths: [String] {
        projects.map(\.project.path)
    }

    var projectColors: [Color] {
        projects.map(\.color)
    }

    func project(path: String) -> DashboardProject? {
        projects.first { $0.project.path == path }
    }

    func dateRangeLabel() -> String {
        "\(rangeStart.formatted(.dateTime.month(.abbreviated).day()))–\(today.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var latestTaskEvents: [FactoryLogEvent] {
        let filteredEvents: [FactoryLogEvent]
        if let selectedProjectPath {
            filteredEvents = events.filter { $0.project.path == selectedProjectPath }
        } else {
            filteredEvents = events
        }

        return Dictionary(grouping: filteredEvents, by: \.taskID)
            .values
            .compactMap { $0.max(by: { $0.timestamp < $1.timestamp }) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Updates per day, including the counts that history compaction folded into
    /// daily aggregates.
    private func dayCounts(from start: Date, to end: Date) -> [Date: Int] {
        let periodEvents = filter(events.filter { $0.timestamp >= start && $0.timestamp < end })
        var counts = Dictionary(grouping: periodEvents) { calendar.startOfDay(for: $0.timestamp) }
            .mapValues(\.count)

        for aggregate in dailyAggregates {
            let day = calendar.startOfDay(for: aggregate.day)
            guard day >= start, day < end else { continue }
            if let selectedProjectPath, aggregate.project.path != selectedProjectPath {
                continue
            }
            counts[day, default: 0] += aggregate.updateCount
        }

        return counts
    }

    private func filter(_ source: [FactoryLogEvent]) -> [FactoryLogEvent] {
        guard let selectedProjectPath else {
            return source
        }
        return source.filter { $0.project.path == selectedProjectPath }
    }

    private func daySeries(from start: Date, count: Int, events: [FactoryLogEvent]) -> [DashboardDay] {
        let counts = Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp) }
            .mapValues(\.count)

        return daySeries(from: start, count: count, counts: counts)
    }

    private func daySeries(from start: Date, count: Int, counts: [Date: Int]) -> [DashboardDay] {
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return DashboardDay(date: date, count: counts[date, default: 0], isFuture: date > today)
        }
    }

    static func color(for path: String) -> Color {
        ProjectPalette.color(for: path)
    }
}

struct DashboardProject: Identifiable {
    let project: FactoryLogEvent.Project
    let updateCount: Int
    let taskCount: Int
    let latestEvent: FactoryLogEvent
    let color: Color

    var id: String { project.path }
}

struct DashboardDay: Identifiable {
    let date: Date
    let count: Int
    let isFuture: Bool

    var id: Date { date }
}

struct DashboardActivityKey: Hashable {
    let day: Date
    let projectPath: String
}

struct DashboardStackPoint: Identifiable {
    let day: Date
    let projectPath: String
    let projectName: String
    let count: Int
    let stackStart: Int
    let stackEnd: Int

    var id: String {
        "\(day.timeIntervalSinceReferenceDate)-\(projectPath)"
    }
}
