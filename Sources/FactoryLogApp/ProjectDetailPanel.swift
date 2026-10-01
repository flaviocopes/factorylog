import Charts
import SwiftUI
import FactoryLogCore

/// One project over the chosen period: how much time it took, when, and the
/// tasks that filled it.
struct ProjectDetailPanel: View {
    let project: FactoryLogEvent.Project
    let snapshot: DashboardSnapshot
    let activeTime: FactoryLogActiveTime
    @Binding var range: ProjectTimeRange
    let onClose: () -> Void

    private var color: Color {
        DashboardSnapshot.color(for: project.path)
    }

    private var rangeStart: Date? {
        range.start(today: snapshot.today, calendar: snapshot.calendar)
    }

    var body: some View {
        let rangeEvents = snapshot.events(in: range)
        let projectEvents = rangeEvents.filter { $0.project.path == project.path }
        let tasks = FactoryLogHistory(events: snapshot.events.filter { $0.project.path == project.path })
            .tasks(activeIn: DateInterval(start: rangeStart ?? .distantPast, end: .distantFuture))

        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ProjectTimeRangePicker(range: $range)

                    stats(
                        projectEvents: projectEvents,
                        totalSeconds: activeTime.seconds(for: rangeEvents),
                        taskCount: tasks.count
                    )

                    if projectEvents.isEmpty {
                        Text("No activity in this period.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        timeChart(projectEvents)
                        taskList(tasks)
                    }
                }
                .padding(20)
            }
            .id(project.path)
        }
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            Divider()
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: -3)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(NSString(string: project.path).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(20)
    }

    private func stats(projectEvents: [FactoryLogEvent], totalSeconds: TimeInterval, taskCount: Int) -> some View {
        let seconds = activeTime.seconds(for: projectEvents)
        let activeDays = Set(projectEvents.map { snapshot.calendar.startOfDay(for: $0.timestamp) }).count

        return VStack(alignment: .leading, spacing: 10) {
            Text(range.periodDescription.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    stat(
                        ActiveTimeFormat.text(seconds),
                        label: totalSeconds > 0
                            ? "Active time · \(ActiveTimeFormat.share(seconds / totalSeconds)) of all"
                            : "Active time"
                    )
                    .help(ActiveTimeFormat.explanation)
                    stat(projectEvents.count.formatted(), label: projectEvents.count == 1 ? "Update" : "Updates")
                }
                GridRow {
                    stat(taskCount.formatted(), label: taskCount == 1 ? "Task" : "Tasks")
                    stat(activeDays.formatted(), label: activeDays == 1 ? "Active day" : "Active days")
                }
            }
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(padding: 12)
    }

    private func timeChart(_ projectEvents: [FactoryLogEvent]) -> some View {
        let calendar = snapshot.calendar
        let unit = range.chartUnit
        var secondsByBucket: [Date: TimeInterval] = [:]
        for event in projectEvents {
            guard let bucket = calendar.dateInterval(of: unit, for: event.timestamp)?.start else {
                continue
            }
            secondsByBucket[bucket, default: 0] += activeTime.seconds(for: event)
        }
        let buckets = secondsByBucket
            .map { ProjectTimeBucket(start: $0.key, seconds: $0.value) }
            .sorted { $0.start < $1.start }

        let firstDate = rangeStart ?? buckets.first?.start ?? snapshot.today
        let domainStart = calendar.dateInterval(of: unit, for: firstDate)?.start ?? firstDate
        let domainEnd = calendar.dateInterval(of: unit, for: snapshot.today)?.end ?? snapshot.rangeEnd

        return VStack(alignment: .leading, spacing: 10) {
            Text(unit == .day ? "Active time per day" : "Active time per week")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.start, unit: unit),
                    y: .value("Hours", bucket.seconds / 3_600)
                )
                .foregroundStyle(color)
                .cornerRadius(2)
                .accessibilityLabel(bucket.start.formatted(.dateTime.month().day()))
                .accessibilityValue(ActiveTimeFormat.text(bucket.seconds))
            }
            .chartXScale(domain: domainStart...domainEnd)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours.formatted(.number.precision(.fractionLength(0...1))))h")
                        }
                    }
                }
            }
            .frame(height: 140)
        }
    }

    private func taskList(_ tasks: [FactoryLogTask]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What you did")
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(taskRows(tasks, now: context.date)) { row in
                        ProjectTaskRow(row: row)
                        if row.id != tasks.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    /// Newest first, with a time label only where it differs from the row above.
    private func taskRows(_ tasks: [FactoryLogTask], now: Date) -> [ProjectTaskRowModel] {
        var rows: [ProjectTaskRowModel] = []
        var shownLabel: String?

        for task in tasks {
            let rangeEvents = task.events.filter { event in
                rangeStart.map { event.timestamp >= $0 } ?? true
            }
            let updatedAt = rangeEvents.last?.timestamp ?? task.lastUpdatedAt
            let label = relativeLabel(for: updatedAt, now: now)
            rows.append(
                ProjectTaskRowModel(
                    task: task,
                    summary: task.events.last { !$0.isAutomaticArchive }?.summary,
                    seconds: activeTime.seconds(for: rangeEvents),
                    updatedAt: updatedAt,
                    timeLabel: label == shownLabel ? nil : label
                )
            )
            shownLabel = label
        }
        return rows
    }

    private func relativeLabel(for date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else {
            return "just now"
        }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

private struct ProjectTimeBucket: Identifiable {
    let start: Date
    let seconds: TimeInterval

    var id: Date { start }
}

private struct ProjectTaskRowModel: Identifiable {
    let task: FactoryLogTask
    let summary: String?
    let seconds: TimeInterval
    let updatedAt: Date
    /// `nil` when the row above already carries this label.
    let timeLabel: String?

    var id: FactoryLogTask.ID { task.id }
}

private struct ProjectTaskRow: View {
    let row: ProjectTaskRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Only unfinished work is flagged; the width is reserved either way
            // so titles stay aligned down the column.
            Group {
                if row.task.status == .doing {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .help("Doing")
                }
            }
            .frame(width: 8, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.task.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                if let summary = row.summary, summary != row.task.title {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.timeLabel ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(row.updatedAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))

                Text(ActiveTimeFormat.text(row.seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(ActiveTimeFormat.explanation)
            }
            .fixedSize()
        }
        .padding(.vertical, 10)
    }
}
