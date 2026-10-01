import Charts
import SwiftUI
import FactoryLogCore

struct DashboardModeHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .tracking(1)

            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardHeatmap: View {
    let snapshot: DashboardSnapshot
    let title: String
    let compact: Bool
    let weekCount: Int
    let onSelectDay: ((Date) -> Void)?
    private let days: [DashboardDay]

    init(
        snapshot: DashboardSnapshot,
        title: String = "12-week activity",
        compact: Bool = false,
        weekCount: Int = 12,
        onSelectDay: ((Date) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.title = title
        self.compact = compact
        self.weekCount = weekCount
        self.onSelectDay = onSelectDay
        self.days = snapshot.activityDays(forWeeks: weekCount)
    }

    private var maxCount: Int {
        max(days.map(\.count).max() ?? 0, 1)
    }

    private var cellSize: CGFloat {
        compact ? 10 : 14
    }

    private var weekdayLabels: [String] {
        let symbols = snapshot.calendar.veryShortStandaloneWeekdaySymbols
        let start = max(snapshot.calendar.firstWeekday - 1, 0)
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(compact ? .callout.weight(.semibold) : .headline)

                Spacer()

                Text("\(weekCount) weeks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 7) {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<7, id: \.self) { weekday in
                        GridRow {
                            Text(weekday % 2 == 0 ? weekdayLabels[weekday] : "")
                                .font(.system(size: compact ? 7 : 9))
                                .foregroundStyle(.tertiary)
                                .frame(width: compact ? 8 : 12)

                            ForEach(0..<weekCount, id: \.self) { week in
                                let day = days[(week * 7) + weekday]
                                RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                                    .fill(color(for: day))
                                    .frame(width: cellSize, height: cellSize)
                                    .help(heatmapHelp(for: day))
                                    .onTapGesture {
                                        if !day.isFuture {
                                            onSelectDay?(day.date)
                                        }
                                    }
                                    .accessibilityLabel(day.date.formatted(.dateTime.month().day().year()))
                                    .accessibilityValue("\(day.count) updates")
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if !compact {
                HStack(spacing: 5) {
                    Spacer()
                    Text("Less")
                    ForEach(1...5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(Double(level) * 0.18))
                            .frame(width: 11, height: 11)
                    }
                    Text("More")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for day: DashboardDay) -> Color {
        if day.isFuture {
            return Color.secondary.opacity(0.06)
        }
        guard day.count > 0 else {
            return Color.secondary.opacity(0.10)
        }
        let ratio = min(Double(day.count) / Double(maxCount), 1)
        return Color.accentColor.opacity(0.22 + (ratio * 0.73))
    }

    private func heatmapHelp(for day: DashboardDay) -> String {
        if day.isFuture {
            return day.date.formatted(.dateTime.weekday(.wide).month().day())
        }
        let updateWord = day.count == 1 ? "update" : "updates"
        return "\(day.date.formatted(.dateTime.weekday(.wide).month().day())): \(day.count) \(updateWord)"
    }
}

struct DashboardStackedActivityChart: View {
    let snapshot: DashboardSnapshot
    @Binding var selectedProjectPath: String?
    var height: CGFloat = 280
    @State private var hoveredPoint: DashboardStackPoint?

    var body: some View {
        if snapshot.stackPoints.isEmpty {
            ContentUnavailableView(
                "No activity in this period",
                systemImage: "chart.bar.xaxis",
                description: Text("Agent updates will appear here.")
            )
            .frame(maxWidth: .infinity, minHeight: height)
        } else {
            Chart(snapshot.stackPoints) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    yStart: .value("Stack start", point.stackStart),
                    yEnd: .value("Stack end", point.stackEnd)
                )
                .foregroundStyle(by: .value("Project", point.projectPath))
                .accessibilityLabel("\(point.projectName), \(point.day.formatted(.dateTime.month().day()))")
                .accessibilityValue("\(point.count) updates")
            }
            .chartForegroundStyleScale(domain: snapshot.projectPaths, range: snapshot.projectColors)
            .chartLegend(.hidden)
            .chartXScale(domain: snapshot.rangeStart...snapshot.rangeEnd)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]

                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        hoveredPoint = chartPoint(at: location, proxy: proxy, plotFrame: plotFrame)
                                    case .ended:
                                        hoveredPoint = nil
                                    }
                                }
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            guard let point = chartPoint(
                                                at: value.location,
                                                proxy: proxy,
                                                plotFrame: plotFrame
                                            ) else {
                                                return
                                            }
                                            toggleProject(point.projectPath)
                                        }
                                )

                            if let hoveredPoint,
                               let x = proxy.position(forX: hoveredPoint.day),
                               let y = proxy.position(
                                   forY: Double(hoveredPoint.stackStart + hoveredPoint.stackEnd) / 2
                               ) {
                                DashboardChartHoverLabel(point: hoveredPoint)
                                    .position(
                                        x: min(max(plotFrame.minX + x, plotFrame.minX + 90), plotFrame.maxX - 90),
                                        y: max(plotFrame.minY + y - 26, plotFrame.minY + 18)
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func toggleProject(_ path: String) {
        selectedProjectPath = selectedProjectPath == path ? nil : path
    }

    private func chartPoint(
        at location: CGPoint,
        proxy: ChartProxy,
        plotFrame: CGRect
    ) -> DashboardStackPoint? {
        guard plotFrame.contains(location),
              let date: Date = proxy.value(atX: location.x - plotFrame.minX),
              let value: Double = proxy.value(atY: location.y - plotFrame.minY) else {
            return nil
        }

        let day = snapshot.calendar.startOfDay(for: date)
        return snapshot.stackPoints.first { point in
            point.day == day
                && value >= Double(point.stackStart)
                && value <= Double(point.stackEnd)
        }
    }
}

struct DashboardEventRow: View {
    let event: FactoryLogEvent
    var showSummary = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind == .archived ? "checkmark.circle.fill" : "circle.fill")
                .font(event.kind == .archived ? .body : .system(size: 8))
                .foregroundStyle(event.kind == .archived ? Color.green : Color.accentColor)
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(event.project.name)
                        .font(.callout.weight(.semibold))
                    Text(event.taskTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showSummary {
                    Text(event.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            RelativeTimeText(date: event.timestamp)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct DashboardChartHoverLabel: View {
    let point: DashboardStackPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.projectName)
                .fontWeight(.semibold)
            Text("\(point.count) \(point.count == 1 ? "update" : "updates")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }
    }
}
