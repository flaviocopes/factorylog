import SwiftUI
import FactoryLogCore

/// The project-first work overview shown when the Factory Log logo is selected.
struct ActivityDashboardView: View {
    let events: [FactoryLogEvent]
    let dailyAggregates: [FactoryLogDailyAggregate]
    let activeTime: FactoryLogActiveTime
    @Binding var selectedProjectPath: String?
    let loadError: String?
    let isLoading: Bool
    let onSelectDay: (Date) -> Void

    @AppStorage(ProjectTimeRange.storageKey) private var timeRange = ProjectTimeRange.month

    private var snapshot: DashboardSnapshot {
        DashboardSnapshot(
            events: events,
            dailyAggregates: dailyAggregates,
            selectedProjectPath: selectedProjectPath
        )
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not read the factory log",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if isLoading && events.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    PortfolioDashboardView(
                        snapshot: snapshot,
                        activeTime: activeTime,
                        timeRange: $timeRange,
                        selectedProjectPath: $selectedProjectPath,
                        onSelectDay: onSelectDay
                    )
                    .frame(maxWidth: 1_100, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .overlay(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        if let project = snapshot.selectedProject {
                            ProjectDetailPanel(
                                project: project,
                                snapshot: snapshot,
                                activeTime: activeTime,
                                range: $timeRange
                            ) {
                                selectedProjectPath = nil
                            }
                            .transition(.move(edge: .trailing))
                        }
                    }
                    .animation(.snappy(duration: 0.22), value: selectedProjectPath == nil)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(closeShortcut)
    }

    private var closeShortcut: some View {
        Button("Close Project") {
            selectedProjectPath = nil
        }
        .keyboardShortcut(.escape, modifiers: [])
        .disabled(selectedProjectPath == nil)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
