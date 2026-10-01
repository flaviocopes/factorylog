import SwiftUI
import FactoryLogCore

enum ProjectTimeRange: String, CaseIterable, Identifiable {
    static let storageKey = "projectTimeRange"

    case week = "7"
    case month = "30"
    case quarter = "90"
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .all: "All time"
        }
    }

    var periodDescription: String {
        switch self {
        case .all: "All time"
        default: "Last \(label)"
        }
    }

    /// Short ranges chart each day; longer ones would turn daily bars into slivers.
    var chartUnit: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter, .all: .weekOfYear
        }
    }

    /// `nil` for all time.
    func start(today: Date, calendar: Calendar) -> Date? {
        guard let days = Int(rawValue) else {
            return nil
        }
        return calendar.date(byAdding: .day, value: -(days - 1), to: today)
    }
}

enum ActiveTimeFormat {
    static let explanation = "Estimated from agent activity. Updates in a project less than 45 minutes apart count as one work session, and each session adds 5 minutes for the work before its first update."

    static func text(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours >= 10 || remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func share(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        return percent == 0 && fraction > 0 ? "<1%" : "\(percent)%"
    }
}

struct ProjectTimeShare: Identifiable {
    let project: FactoryLogEvent.Project
    let seconds: TimeInterval
    let fraction: Double
    let color: Color

    var id: String { project.path }
}

extension DashboardSnapshot {
    func events(in range: ProjectTimeRange) -> [FactoryLogEvent] {
        guard let start = range.start(today: today, calendar: calendar) else {
            return events
        }
        return events.filter { $0.timestamp >= start }
    }

    func timeShares(in range: ProjectTimeRange, activeTime: FactoryLogActiveTime) -> [ProjectTimeShare] {
        let secondsByPath = Dictionary(grouping: events(in: range), by: \.project.path)
            .mapValues { (project: $0[0].project, seconds: activeTime.seconds(for: $0)) }
            .filter { $0.value.seconds > 0 }
        let total = secondsByPath.values.reduce(0) { $0 + $1.seconds }

        return secondsByPath.values
            .map { entry in
                ProjectTimeShare(
                    project: entry.project,
                    seconds: entry.seconds,
                    fraction: total > 0 ? entry.seconds / total : 0,
                    color: Self.color(for: entry.project.path)
                )
            }
            .sorted {
                if $0.seconds != $1.seconds {
                    return $0.seconds > $1.seconds
                }
                return $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
            }
    }
}

/// Ranks projects by estimated active time so the split of the week, month or
/// longer is readable at a glance.
struct TimeInvestmentCard: View {
    let snapshot: DashboardSnapshot
    let activeTime: FactoryLogActiveTime
    @Binding var range: ProjectTimeRange
    @Binding var selectedProjectPath: String?
    @State private var showsAllProjects = false

    private let collapsedCount = 6

    var body: some View {
        let shares = snapshot.timeShares(in: range, activeTime: activeTime)
        let total = shares.reduce(0) { $0 + $1.seconds }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where your time went")
                        .font(.headline)

                    Label {
                        Text(summary(total: total, projectCount: shares.count))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(ActiveTimeFormat.explanation)
                }

                Spacer()

                ProjectTimeRangePicker(range: $range)
            }

            if shares.isEmpty {
                Text("No agent activity in this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                HStack(alignment: .top, spacing: 30) {
                    ProjectTimeDonut(shares: shares, selectedProjectPath: selectedProjectPath, size: 200)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(showsAllProjects ? shares : Array(shares.prefix(collapsedCount))) { share in
                            row(share, topSeconds: shares[0].seconds)
                        }

                        if shares.count > collapsedCount {
                            Button(showsAllProjects ? "Show fewer" : "Show \(shares.count - collapsedCount) more projects") {
                                showsAllProjects.toggle()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .padding(.leading, 8)
                            .padding(.top, 6)
                        }
                    }
                }
            }
        }
        .dashboardCard()
    }

    private func summary(total: TimeInterval, projectCount: Int) -> String {
        let projectWord = projectCount == 1 ? "project" : "projects"
        return "\(ActiveTimeFormat.text(total)) of active time across \(projectCount) \(projectWord)"
    }

    private func row(_ share: ProjectTimeShare, topSeconds: TimeInterval) -> some View {
        let isSelected = selectedProjectPath == share.project.path

        return Button {
            toggle(share.project.path)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(share.color)
                    .frame(width: 8, height: 8)

                Text(share.project.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 190, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(share.color.gradient)
                            .frame(width: max(geometry.size.width * share.seconds / max(topSeconds, 1), 6))
                    }
                }
                .frame(height: 8)

                Text(ActiveTimeFormat.text(share.seconds))
                    .font(.callout.monospacedDigit())
                    .frame(width: 64, alignment: .trailing)

                Text(ActiveTimeFormat.share(share.fraction))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hidesProjectOnRightClick(share.project)
        .help(isSelected ? "Close \(share.project.name)" : "Show what you did in \(share.project.name)")
    }

    private func toggle(_ path: String) {
        selectedProjectPath = selectedProjectPath == path ? nil : path
    }
}

struct ProjectTimeRangePicker: View {
    @Binding var range: ProjectTimeRange

    var body: some View {
        Picker("Period", selection: $range) {
            ForEach(ProjectTimeRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
