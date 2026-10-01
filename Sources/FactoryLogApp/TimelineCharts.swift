import Charts
import SwiftUI
import FactoryLogCore

/// A session cut to the part that falls inside one day.
struct TimelineSegment: Identifiable {
    let session: FactoryLogWorkSession
    let start: Date
    let end: Date

    var id: String { "\(session.id)|\(start.timeIntervalSinceReferenceDate)" }
    var project: FactoryLogEvent.Project { session.project }
    var color: Color { DashboardSnapshot.color(for: session.project.path) }

    static func clip(_ sessions: [FactoryLogWorkSession], to interval: DateInterval) -> [TimelineSegment] {
        sessions.compactMap { session in
            let start = max(session.start, interval.start)
            let end = min(session.end, interval.end)
            guard end > start else {
                return nil
            }
            return TimelineSegment(session: session, start: start, end: end)
        }
    }
}

/// One lane per project across the hours of a single day, so the day reads as
/// a schedule: what you worked on, when, and for how long.
struct DayTimelineChart: View {
    let segments: [TimelineSegment]
    let day: DateInterval
    let secondsByProject: [String: TimeInterval]
    let showsNow: Bool
    @Binding var selectedProjectPath: String?

    @State private var hovered: TimelineSegment?

    private var lanes: [FactoryLogEvent.Project] {
        var projects: [String: FactoryLogEvent.Project] = [:]
        for segment in segments {
            projects[segment.project.path] = segment.project
        }
        return projects.values.sorted {
            let left = secondsByProject[$0.path] ?? 0
            let right = secondsByProject[$1.path] ?? 0
            if left != right {
                return left > right
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let earliest = segments.map(\.start).min() ?? day.start
        var latest = segments.map(\.end).max() ?? day.end
        if showsNow {
            latest = max(latest, Date())
        }
        let start = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        var end = calendar.dateInterval(of: .hour, for: latest)?.end ?? latest
        if end.timeIntervalSince(start) < 4 * 3_600 {
            end = start.addingTimeInterval(4 * 3_600)
        }
        return max(start, day.start)...min(end, day.end)
    }

    private var hourStride: Int {
        let hours = domain.upperBound.timeIntervalSince(domain.lowerBound) / 3_600
        return hours > 12 ? 2 : 1
    }

    var body: some View {
        let lanes = lanes
        let rows = TimelineRows(keys: lanes.map(\.path))
        let bars = TimelineBar.place(segments, rows: rows) { $0.project.path }

        Chart {
            marks(bars)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: rows.domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: hourStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: rows.centers) { value in
                AxisValueLabel {
                    laneLabel(at: value.as(Double.self), rows: rows, lanes: lanes)
                }
            }
        }
        .chartOverlay { proxy in
            overlay(proxy: proxy, rows: rows)
        }
        .frame(height: CGFloat(lanes.count) * 36 + 34)
    }

    @ChartContentBuilder
    private func marks(_ bars: [TimelineBar]) -> some ChartContent {
        ForEach(bars) { bar in
            RectangleMark(
                xStart: .value("Start", bar.segment.start),
                xEnd: .value("End", bar.segment.end),
                yStart: .value("Lane", bar.band.lowerBound),
                yEnd: .value("Lane", bar.band.upperBound)
            )
            .foregroundStyle(bar.segment.color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(isDimmed(bar.segment.project.path) ? 0.22 : 1)
        }

        if showsNow, domain.contains(Date()) {
            RuleMark(x: .value("Now", Date()))
                .foregroundStyle(Color.red.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .annotation(position: .top, spacing: 2) {
                    Text("now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
        }
    }

    private func overlay(proxy: ChartProxy, rows: TimelineRows) -> some View {
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
                                hovered = segment(at: location, rows: rows, proxy: proxy, plotFrame: plotFrame)
                            case .ended:
                                hovered = nil
                            }
                        }
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                guard let segment = segment(at: value.location, rows: rows, proxy: proxy, plotFrame: plotFrame) else {
                                    return
                                }
                                let path = segment.project.path
                                selectedProjectPath = selectedProjectPath == path ? nil : path
                            }
                        )

                    if let hovered,
                       let x = proxy.position(forX: hovered.start),
                       let center = rows.center(for: hovered.project.path),
                       let y = proxy.position(forY: center) {
                        ChartTooltip(
                            title: hovered.project.name,
                            subtitle: "\(timeRange(hovered)) · \(ActiveTimeFormat.text(hovered.end.timeIntervalSince(hovered.start)))",
                            lines: taskTitles(hovered.session),
                            color: hovered.color
                        )
                        .fixedSize()
                        .position(
                            x: min(max(plotFrame.minX + x + 110, plotFrame.minX + 110), plotFrame.maxX - 110),
                            y: plotFrame.minY + y + 48
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func laneLabel(at center: Double?, rows: TimelineRows, lanes: [FactoryLogEvent.Project]) -> some View {
        if let center, let path = rows.key(at: center), let project = lanes.first(where: { $0.path == path }) {
            laneLabel(path: project.path, name: project.name)
        }
    }

    private func laneLabel(path: String, name: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(DashboardSnapshot.color(for: path))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.callout.weight(.medium))
                .foregroundStyle(isDimmed(path) ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(ActiveTimeFormat.text(secondsByProject[path] ?? 0))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 230)
    }

    private func isDimmed(_ path: String) -> Bool {
        guard let selectedProjectPath else {
            return false
        }
        return selectedProjectPath != path
    }

    private func segment(at location: CGPoint, rows: TimelineRows, proxy: ChartProxy, plotFrame: CGRect) -> TimelineSegment? {
        guard plotFrame.contains(location),
              let date: Date = proxy.value(atX: location.x - plotFrame.minX),
              let lane: Double = proxy.value(atY: location.y - plotFrame.minY),
              let path = rows.key(at: lane) else {
            return nil
        }
        // A five-minute session is a sliver, so allow a little slack around it.
        let slack: TimeInterval = 4 * 60
        return segments.first {
            $0.project.path == path && date >= $0.start.addingTimeInterval(-slack) && date <= $0.end.addingTimeInterval(slack)
        }
    }

    private func timeRange(_ segment: TimelineSegment) -> String {
        let format = Date.FormatStyle.dateTime.hour().minute()
        return "\(segment.start.formatted(format))–\(segment.end.formatted(format))"
    }
}

/// Seven rows, one per day, across the hours of the day. A week of work reads
/// like a calendar: when you started, when you stopped, and what filled it.
struct WeekRibbonChart: View {
    let days: [Date]
    let segments: [TimelineSegment]
    let secondsByDay: [Date: TimeInterval]
    let today: Date
    let onSelectDay: (Date) -> Void

    @State private var hovered: TimelineSegment?
    @State private var hoveredDay: Date?

    private let calendar = Calendar.current

    private var hourDomain: ClosedRange<Double> {
        let starts = segments.map { hour(of: $0.start) }
        let ends = segments.map { hour(of: $0.end, isEnd: true) }
        guard let first = starts.min(), let last = ends.max() else {
            return 8...20
        }
        var lower = first.rounded(.down)
        var upper = last.rounded(.up)
        if upper - lower < 8 {
            let padding = (8 - (upper - lower)) / 2
            lower = max(0, lower - padding.rounded(.down))
            upper = min(24, lower + 8)
        }
        return lower...upper
    }

    var body: some View {
        let domain = hourDomain
        let rows = TimelineRows(keys: days.map(key(for:)))

        let bars = TimelineBar.place(segments, rows: rows) { key(for: $0.start) }

        Chart {
            ForEach(bars) { bar in
                RectangleMark(
                    xStart: .value("Start", hour(of: bar.segment.start)),
                    xEnd: .value("End", hour(of: bar.segment.end, isEnd: true)),
                    yStart: .value("Day", bar.band.lowerBound),
                    yEnd: .value("Day", bar.band.upperBound)
                )
                .foregroundStyle(bar.segment.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: rows.domain)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: domain.lowerBound, through: domain.upperBound, by: domain.upperBound - domain.lowerBound > 12 ? 2 : 1))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(hourLabel(hour))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: rows.centers) { value in
                AxisValueLabel {
                    if let center = value.as(Double.self),
                       let key = rows.key(at: center),
                       let day = days.first(where: { self.key(for: $0) == key }) {
                        dayLabel(day)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(alignment: .topLeading) {
                GeometryReader { geometry in
                    if let hoveredDay, let index = days.firstIndex(of: hoveredDay) {
                        let rowHeight = geometry.size.height / CGFloat(days.count)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.06))
                            .frame(height: rowHeight)
                            .offset(y: rowHeight * CGFloat(index))
                    }
                }
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
                                    hoveredDay = day(at: location, plotFrame: plotFrame)
                                    hovered = segment(at: location, proxy: proxy, plotFrame: plotFrame)
                                case .ended:
                                    hoveredDay = nil
                                    hovered = nil
                                }
                            }
                            .gesture(
                                SpatialTapGesture().onEnded { value in
                                    if let day = day(at: value.location, plotFrame: plotFrame), day <= today {
                                        onSelectDay(day)
                                    }
                                }
                            )

                        if let hovered,
                           let x = proxy.position(forX: hour(of: hovered.start)),
                           let center = rows.center(for: key(for: hovered.start)),
                           let y = proxy.position(forY: center) {
                            ChartTooltip(
                                title: hovered.project.name,
                                subtitle: "\(timeRange(hovered)) · \(ActiveTimeFormat.text(hovered.end.timeIntervalSince(hovered.start)))",
                                lines: taskTitles(hovered.session),
                                color: hovered.color
                            )
                            .fixedSize()
                            .position(
                                x: min(max(plotFrame.minX + x + 110, plotFrame.minX + 110), plotFrame.maxX - 110),
                                y: plotFrame.minY + y + 52
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(days.count) * 40 + 30)
    }

    private func dayLabel(_ day: Date) -> some View {
        let isFuture = day > today
        return HStack(spacing: 8) {
            Text(day, format: .dateTime.weekday(.abbreviated))
                .font(.callout.weight(calendar.isDate(day, inSameDayAs: today) ? .bold : .medium))
                .frame(width: 34, alignment: .leading)
            Text(day, format: .dateTime.day())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if !isFuture {
                Text(secondsByDay[day].map(ActiveTimeFormat.text) ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(secondsByDay[day] == nil ? .tertiary : .secondary)
            }
        }
        .foregroundStyle(isFuture ? .tertiary : .primary)
        .frame(width: 150)
    }

    private func key(for date: Date) -> String {
        let day = calendar.startOfDay(for: date)
        return String(Int(day.timeIntervalSinceReferenceDate))
    }

    /// Hours since the start of the date's day. A segment ending exactly at
    /// midnight belongs to the day it ends, at hour 24.
    private func hour(of date: Date, isEnd: Bool = false) -> Double {
        let dayStart = calendar.startOfDay(for: isEnd ? date.addingTimeInterval(-1) : date)
        return date.timeIntervalSince(dayStart) / 3_600
    }

    private func hourLabel(_ hour: Double) -> String {
        let reference = calendar.startOfDay(for: today).addingTimeInterval(hour * 3_600)
        return reference.formatted(.dateTime.hour())
    }

    private func day(at location: CGPoint, plotFrame: CGRect) -> Date? {
        guard plotFrame.contains(location), !days.isEmpty else {
            return nil
        }
        let rowHeight = plotFrame.height / CGFloat(days.count)
        let index = Int((location.y - plotFrame.minY) / rowHeight)
        return days.indices.contains(index) ? days[index] : nil
    }

    private func segment(at location: CGPoint, proxy: ChartProxy, plotFrame: CGRect) -> TimelineSegment? {
        guard let day = day(at: location, plotFrame: plotFrame),
              let hour: Double = proxy.value(atX: location.x - plotFrame.minX) else {
            return nil
        }
        let slack = 4.0 / 60
        return segments.first {
            calendar.isDate($0.start, inSameDayAs: day)
                && hour >= self.hour(of: $0.start) - slack
                && hour <= self.hour(of: $0.end, isEnd: true) + slack
        }
    }

    private func timeRange(_ segment: TimelineSegment) -> String {
        let format = Date.FormatStyle.dateTime.hour().minute()
        return "\(segment.start.formatted(format))–\(segment.end.formatted(format))"
    }
}

struct TimelineBar: Identifiable {
    let segment: TimelineSegment
    let band: ClosedRange<Double>

    var id: String { segment.id }

    static func place(
        _ segments: [TimelineSegment],
        rows: TimelineRows,
        key: (TimelineSegment) -> String
    ) -> [TimelineBar] {
        segments.compactMap { segment in
            rows.band(for: key(segment)).map { TimelineBar(segment: segment, band: $0) }
        }
    }
}

/// Places keyed rows on a numeric axis, first key at the top. Categorical axes
/// with custom labels drift off their bars, so the timelines place rows
/// themselves.
struct TimelineRows {
    let keys: [String]
    private let barInset = 0.22

    var domain: ClosedRange<Double> {
        0...Double(max(keys.count, 1))
    }

    var centers: [Double] {
        keys.indices.map { Double(keys.count - $0) - 0.5 }
    }

    func band(for key: String) -> ClosedRange<Double>? {
        guard let index = keys.firstIndex(of: key) else {
            return nil
        }
        let top = Double(keys.count - index)
        return (top - 1 + barInset)...(top - barInset)
    }

    func center(for key: String) -> Double? {
        band(for: key).map { ($0.lowerBound + $0.upperBound) / 2 }
    }

    func key(at value: Double) -> String? {
        let index = keys.count - 1 - Int(value.rounded(.down))
        return keys.indices.contains(index) ? keys[index] : nil
    }
}

/// Each project's share of the time as a ring, with the total in the middle.
/// The long tail shares one gray slice so the ring stays readable.
struct ProjectTimeDonut: View {
    let shares: [ProjectTimeShare]
    let selectedProjectPath: String?
    var size: CGFloat = 190
    var sliceCount = 7

    private var total: TimeInterval {
        shares.reduce(0) { $0 + $1.seconds }
    }

    private var selectedShare: ProjectTimeShare? {
        shares.first { $0.project.path == selectedProjectPath }
    }

    private var slices: [ProjectTimeShare] {
        guard shares.count > sliceCount + 1 else {
            return shares
        }
        let rest = shares.dropFirst(sliceCount)
        let other = ProjectTimeShare(
            project: .init(name: "Other", path: ""),
            seconds: rest.reduce(0) { $0 + $1.seconds },
            fraction: rest.reduce(0) { $0 + $1.fraction },
            color: Color.secondary.opacity(0.35)
        )
        return Array(shares.prefix(sliceCount)) + [other]
    }

    var body: some View {
        Chart(slices) { share in
            SectorMark(
                angle: .value("Time", share.seconds),
                innerRadius: .ratio(0.64),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(share.color)
            .opacity(selectedProjectPath == nil || selectedProjectPath == share.project.path ? 1 : 0.25)
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let frame = geometry[plotFrameAnchor]
                    VStack(spacing: 2) {
                        Text(ActiveTimeFormat.text(selectedShare?.seconds ?? total))
                            .font(.system(size: size * 0.14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(selectedShare.map { ActiveTimeFormat.share($0.fraction) } ?? "active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct ChartTooltip: View {
    let title: String
    let subtitle: String
    var lines: [String] = []
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .fontWeight(.semibold)
            }
            Text(subtitle)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: .leading)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }
}

/// The distinct task titles in a session, capped so a tooltip stays small.
func taskTitles(_ session: FactoryLogWorkSession, limit: Int = 3) -> [String] {
    var seen = Set<String>()
    let titles = session.events.map(\.taskTitle).filter { seen.insert($0).inserted }
    guard titles.count > limit else {
        return titles.map { "• \($0)" }
    }
    return titles.prefix(limit).map { "• \($0)" } + ["+ \(titles.count - limit) more"]
}
