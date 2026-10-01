import SwiftUI
import FactoryLogCore

/// A day at a glance: one block per project instead of every update.
struct DaySummaryView: View {
    let summaries: [FactoryLogProjectSummary]
    let day: Date
    let narratives: DayNarratives
    let secondsByProject: [String: TimeInterval]
    let openProject: (FactoryLogProjectSummary) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(summaries) { summary in
                ProjectSummaryRow(
                    summary: summary,
                    seconds: secondsByProject[summary.project.path] ?? 0,
                    narrative: narratives.state(for: summary, on: day)
                ) {
                    openProject(summary)
                }
                .hidesProjectOnRightClick(summary.project)
                .task(id: summary.signature) {
                    await narratives.load(summary, on: day)
                }
            }
        }
    }
}

private struct ProjectSummaryRow: View {
    let summary: FactoryLogProjectSummary
    let seconds: TimeInterval
    let narrative: DayNarratives.State
    let open: () -> Void

    private var color: Color {
        DashboardSnapshot.color(for: summary.project.path)
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(color)
                        }

                    Text(summary.project.name)
                        .font(.headline)

                    Spacer(minLength: 10)

                    Text(ActiveTimeFormat.text(seconds))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .help("Last update \(summary.lastUpdatedAt.formatted(.dateTime.hour().minute()))")
                }

                // A sentence says everything the counts and titles were standing in
                // for, so they only appear when no sentence was written.
                switch narrative {
                case .missing:
                    rollup
                case .writing:
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Writing the day recap…")
                            .foregroundStyle(.tertiary)
                    }
                case let .written(text):
                    Text(text)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 17)
            .padding(.leading, 21)
            .padding(.trailing, 17)
            .background {
                ZStack(alignment: .leading) {
                    Color(nsColor: .textBackgroundColor)
                    color
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Show this project's tasks for the day")
    }
}

private extension ProjectSummaryRow {
    /// What the day looked like without a model to describe it.
    var rollup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stats)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(summary.tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Only unfinished work is flagged; the width is reserved
                        // either way so titles stay aligned down the column.
                        Group {
                            if task.status == .doing {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(width: 8)

                        Text(task.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var stats: String {
        let taskWord = summary.tasks.count == 1 ? "task" : "tasks"
        var parts = ["\(summary.tasks.count) \(taskWord)"]
        if summary.doingCount > 0 {
            parts.append("\(summary.doingCount) Doing")
        }
        return parts.joined(separator: " · ")
    }
}
