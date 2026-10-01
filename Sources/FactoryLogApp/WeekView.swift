import SwiftUI
import FactoryLogCore

/// A week of work: when it happened, where the time went, and what shipped.
struct WeekView: View {
    let events: [FactoryLogEvent]
    let activeTime: FactoryLogActiveTime
    @Binding var weekOffset: Int
    let onSelectDay: (Date) -> Void

    @State private var selectedProjectPath: String?
    @State private var showsAllShipped = false

    private let calendar = Calendar.current

    var body: some View {
        let model = WeekModel(events: events, activeTime: activeTime, offset: weekOffset, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(model)

                ribbonCard(model)

                HStack(alignment: .top, spacing: 16) {
                    whereCard(model)
                        .frame(maxWidth: .infinity)
                    shippedCard(model)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 1_100, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(shortcuts(model))
        .onChange(of: weekOffset) {
            selectedProjectPath = nil
            showsAllShipped = false
        }
    }

    // MARK: Header

    private func header(_ model: WeekModel) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEEK OF \(model.start.formatted(.dateTime.month(.wide).day()).uppercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1)

                Text(title(model))
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                HStack(spacing: 14) {
                    Text("\(ActiveTimeFormat.text(model.totalSeconds)) of active work")
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(model.activeDayCount) active \(model.activeDayCount == 1 ? "day" : "days")")
                    if let change = model.changePercentage {
                        Text("·").foregroundStyle(.tertiary)
                        Label("\(abs(change))% vs prior week", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(change >= 0 ? Color.green : Color.orange)
                    }
                }
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if weekOffset != 0 {
                    Button("This Week") {
                        weekOffset = 0
                    }
                }

                ControlGroup {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Label("Previous Week", systemImage: "chevron.left")
                    }
                    .disabled(weekOffset <= model.earliestOffset)
                    .help("Previous week")

                    Button {
                        weekOffset += 1
                    } label: {
                        Label("Next Week", systemImage: "chevron.right")
                    }
                    .disabled(weekOffset >= 0)
                    .help("Next week")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
        }
    }

    private func title(_ model: WeekModel) -> String {
        switch weekOffset {
        case 0:
            return "This week"
        case -1:
            return "Last week"
        default:
            let end = calendar.date(byAdding: .day, value: 6, to: model.start) ?? model.start
            let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(model.start.formatted(format)) – \(end.formatted(format))"
        }
    }

    // MARK: Cards

    private func ribbonCard(_ model: WeekModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What you worked on")
                    .font(.headline)
                Spacer()
                Text("Click a day to open it")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            WeekRibbonChart(
                days: model.days,
                segments: model.segments,
                secondsByDay: model.secondsByDay,
                today: model.today,
                onSelectDay: onSelectDay
            )
        }
        .dashboardCard()
    }

    private func whereCard(_ model: WeekModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where the time went")
                .font(.headline)

            if model.shares.isEmpty {
                quietWeek
            } else {
                HStack(alignment: .center, spacing: 22) {
                    ProjectTimeDonut(shares: model.shares, selectedProjectPath: selectedProjectPath, size: 170)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.shares.prefix(6)) { share in
                            shareRow(share)
                        }
                        if model.shares.count > 6 {
                            let rest = model.shares.dropFirst(6)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text("\(rest.count) more")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(ActiveTimeFormat.text(rest.reduce(0) { $0 + $1.seconds }))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCard()
    }

    private func shareRow(_ share: ProjectTimeShare) -> some View {
        let isSelected = selectedProjectPath == share.project.path

        return Button {
            selectedProjectPath = isSelected ? nil : share.project.path
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(share.color)
                    .frame(width: 8, height: 8)
                Text(share.project.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(ActiveTimeFormat.text(share.seconds))
                    .monospacedDigit()
                Text(ActiveTimeFormat.share(share.fraction))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected ? share.color.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hidesProjectOnRightClick(share.project)
    }

    private func shippedCard(_ model: WeekModel) -> some View {
        let shipped = selectedProjectPath.map { path in model.shipped.filter { $0.project.path == path } } ?? model.shipped
        let visible = showsAllShipped ? shipped : Array(shipped.prefix(6))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("What shipped")
                    .font(.headline)
                Spacer()
                Text("\(shipped.count) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if shipped.isEmpty {
                quietWeek
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { event in
                        shippedRow(event)
                        if event.id != visible.last?.id {
                            Divider()
                        }
                    }
                }

                if shipped.count > 6 {
                    Button(showsAllShipped ? "Show fewer" : "Show all \(shipped.count)") {
                        showsAllShipped.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCard()
    }

    private func shippedRow(_ event: FactoryLogEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(DashboardSnapshot.color(for: event.project.path))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.taskTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(event.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(event.timestamp, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var quietWeek: some View {
        Text("No agent activity this week.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func shortcuts(_ model: WeekModel) -> some View {
        ZStack {
            Button("Previous Week") {
                weekOffset -= 1
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(weekOffset <= model.earliestOffset)

            Button("Next Week") {
                weekOffset += 1
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(weekOffset >= 0)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything the week view derives from the log, computed once per render.
private struct WeekModel {
    let today: Date
    let start: Date
    let days: [Date]
    let segments: [TimelineSegment]
    let secondsByDay: [Date: TimeInterval]
    let shares: [ProjectTimeShare]
    let shipped: [FactoryLogEvent]
    let totalSeconds: TimeInterval
    let changePercentage: Int?
    let earliestOffset: Int

    var activeDayCount: Int {
        secondsByDay.count
    }

    init(events: [FactoryLogEvent], activeTime: FactoryLogActiveTime, offset: Int, calendar: Calendar) {
        today = calendar.startOfDay(for: Date())
        let currentStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        start = calendar.date(byAdding: .weekOfYear, value: offset, to: currentStart) ?? currentStart
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let start = start
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        self.days = days

        let weekEvents = events.filter { $0.timestamp >= start && $0.timestamp < end }
        let previousEvents = events.filter { $0.timestamp >= previousStart && $0.timestamp < start }

        totalSeconds = activeTime.seconds(for: weekEvents)
        let previousSeconds = activeTime.seconds(for: previousEvents)
        changePercentage = previousSeconds > 0
            ? Int(((totalSeconds - previousSeconds) / previousSeconds * 100).rounded())
            : nil

        secondsByDay = Dictionary(grouping: weekEvents) { calendar.startOfDay(for: $0.timestamp) }
            .mapValues { activeTime.seconds(for: $0) }
            .filter { $0.value > 0 }

        let visiblePaths = Set(weekEvents.map(\.project.path))
        let sessions = activeTime.sessions(overlapping: DateInterval(start: start, end: end))
            .filter { visiblePaths.contains($0.project.path) }
        segments = days.flatMap { day in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return TimelineSegment.clip(sessions, to: DateInterval(start: day, end: dayEnd))
        }

        let secondsByPath = Dictionary(grouping: weekEvents, by: \.project.path)
            .mapValues { (project: $0[0].project, seconds: activeTime.seconds(for: $0)) }
            .filter { $0.value.seconds > 0 }
        let total = secondsByPath.values.reduce(0) { $0 + $1.seconds }
        shares = secondsByPath.values
            .map {
                ProjectTimeShare(
                    project: $0.project,
                    seconds: $0.seconds,
                    fraction: total > 0 ? $0.seconds / total : 0,
                    color: DashboardSnapshot.color(for: $0.project.path)
                )
            }
            .sorted { $0.seconds > $1.seconds }

        shipped = weekEvents
            .filter { $0.kind == .archived && !$0.isAutomaticArchive }
            .sorted { $0.timestamp > $1.timestamp }

        let earliest = events.map(\.timestamp).min() ?? today
        let earliestStart = calendar.dateInterval(of: .weekOfYear, for: earliest)?.start ?? earliest
        earliestOffset = min(calendar.dateComponents([.weekOfYear], from: currentStart, to: earliestStart).weekOfYear ?? 0, 0)
    }
}
