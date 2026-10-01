import SwiftUI
import FactoryLogCore

/// The Insights screen: time by project over a chosen range, long-range activity,
/// the busiest projects, and the latest outcomes.
struct PortfolioDashboardView: View {
    let snapshot: DashboardSnapshot
    let activeTime: FactoryLogActiveTime
    @Binding var timeRange: ProjectTimeRange
    @Binding var selectedProjectPath: String?
    let onSelectDay: (Date) -> Void

    private let columns = [
        GridItem(.flexible(minimum: 210), spacing: 12),
        GridItem(.flexible(minimum: 210), spacing: 12),
        GridItem(.flexible(minimum: 210), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashboardModeHeader(
                eyebrow: "Insights",
                title: snapshot.selectedProject.map(\.name) ?? "The long view",
                subtitle: "Where your time goes over weeks and months, and which projects carry the momentum."
            )

            TimeInvestmentCard(
                snapshot: snapshot,
                activeTime: activeTime,
                range: $timeRange,
                selectedProjectPath: $selectedProjectPath
            )

            HStack(alignment: .top, spacing: 16) {
                DashboardHeatmap(snapshot: snapshot, title: "26-week activity", weekCount: 26, onSelectDay: onSelectDay)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .dashboardCard()
                    .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 14) {
                    Text("30-day project activity")
                        .font(.headline)

                    DashboardStackedActivityChart(
                        snapshot: snapshot,
                        selectedProjectPath: $selectedProjectPath,
                        height: 190
                    )
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .dashboardCard()
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(snapshot.projects.prefix(9)) { project in
                    PortfolioProjectCard(
                        project: project,
                        isSelected: selectedProjectPath == project.project.path
                    ) {
                        selectedProjectPath = selectedProjectPath == project.project.path ? nil : project.project.path
                    }
                    .hidesProjectOnRightClick(project.project)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Latest outcomes")
                    .font(.headline)
                ForEach(snapshot.recentOutcomes.prefix(4)) { event in
                    DashboardEventRow(event: event, showSummary: false)
                    if event.id != snapshot.recentOutcomes.prefix(4).last?.id {
                        Divider()
                    }
                }
            }
            .dashboardCard()
        }
    }
}

private struct PortfolioProjectCard: View {
    let project: DashboardProject
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(project.color.opacity(0.14))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(project.color)
                        }

                    Text(project.project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(project.updateCount, format: .number)
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(project.taskCount) tasks")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("Latest outcome")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(project.latestEvent.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(17)
            .background(project.color.opacity(isSelected ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? project.color : project.color.opacity(0.22), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}
