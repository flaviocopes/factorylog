import AppKit
import SwiftUI
import FactoryLogCore

@main
struct FactoryLogApp: App {
    init() {
        AppUpdater.shared.start(repository: "flaviocopes/factorylog")

        #if DEBUG
        if DebugSnapshot.usesActiveWindow {
            DispatchQueue.main.async {
                DebugSnapshot.openActiveWindow(ContentView())
            }
        }
        #endif

        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }

    private static var launchBehavior: SceneLaunchBehavior {
        #if DEBUG
        DebugSnapshot.usesActiveWindow ? .suppressed : .automatic
        #else
        .automatic
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultLaunchBehavior(Self.launchBehavior)
        .defaultSize(width: 1_280, height: 860)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppUpdater.shared.checkForUpdates()
                }
            }
        }

        Settings {
            AppSettingsView()
        }
    }
}

enum AppScreen: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case week
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Week"
        case .insights: "Insights"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .yesterday: "2"
        case .week: "3"
        case .insights: "4"
        }
    }
}

private struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(HiddenProjects.storageKey) private var hiddenProjects = HiddenProjects()
    @State private var events: [FactoryLogEvent] = []
    @State private var hasLoaded = false
    @State private var dailyAggregates: [FactoryLogDailyAggregate] = []
    @State private var activeTime = FactoryLogActiveTime(events: [])
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var reloadGeneration = 0
    @State private var screen: AppScreen = .today
    /// A day opened from the week or insights view, shown in place of it.
    @State private var openedDay: Date?
    @State private var weekOffset = 0
    @State private var selectedProjectPath: String?
    @State private var narratives = DayNarratives()

    private let store = EventStore()

    /// A new install with no reports yet, as opposed to a quiet stretch.
    private var isFirstRun: Bool {
        hasLoaded && events.isEmpty && loadError == nil
    }

    private var nextAutomaticArchiveDate: Date? {
        FactoryLogHistory(events: events)
            .doingTasks()
            .map { $0.startedAt.addingTimeInterval(EventStore.automaticArchiveInterval) }
            .min()
    }

    private var visibleEvents: [FactoryLogEvent] {
        events.filter { !hiddenProjects.contains($0.project.path) }
    }

    private var visibleDailyAggregates: [FactoryLogDailyAggregate] {
        dailyAggregates.filter { !hiddenProjects.contains($0.project.path) }
    }

    var body: some View {
        content
            .frame(minWidth: 960, minHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(screenShortcuts)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    appIdentity
                }

                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $screen) {
                        ForEach(AppScreen.allCases) { screen in
                            Text(screen.title).tag(screen)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 360)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings")
                }
            }
            .task {
                await reload()
                for await _ in EventStoreWatcher(url: store.url).changes() {
                    await reload()
                }
            }
            .task(id: nextAutomaticArchiveDate) {
                guard let nextAutomaticArchiveDate else {
                    return
                }
                let delay = max(nextAutomaticArchiveDate.timeIntervalSinceNow, 0)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                await reload()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }
                Task {
                    await reload()
                }
            }
            .onChange(of: screen) {
                openedDay = nil
                selectedProjectPath = nil
            }
            .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
            #if DEBUG
            .onReceive(DistributedNotificationCenter.default().publisher(for: DebugSnapshot.notification)) { notification in
                guard let request = DebugSnapshot.Request(notification) else {
                    return
                }
                let parts = request.screen.split(separator: "@", maxSplits: 1).map(String.init)
                if let first = parts.first, let screen = AppScreen(rawValue: first) {
                    self.screen = screen
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    selectedProjectPath = parts.count == 2 ? parts[1] : nil
                    try? await Task.sleep(for: .milliseconds(900))
                    DebugSnapshot.capture(to: request.path)
                }
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let openedDay {
            dayView(openedDay, backTitle: screen.title) {
                self.openedDay = nil
            }
            .id(openedDay)
        } else {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

            switch screen {
            case .today:
                if isFirstRun {
                    WelcomeView()
                } else {
                    let workedYesterday = visibleEvents.contains { calendar.isDate($0.timestamp, inSameDayAs: yesterday) }
                    dayView(today, onShowYesterday: workedYesterday ? { screen = .yesterday } : nil)
                        .id(screen)
                }
            case .yesterday:
                dayView(yesterday)
                    .id(screen)
            case .week:
                if isFirstRun {
                    let sample = SampleWork.events(before: Date())
                    FirstRunPreview(
                        title: "Your week at a glance",
                        message: "One row per day, one bar per work session, colored by project. Next to it, where the week's time went and everything your agents shipped.",
                        onGetStarted: { screen = .today }
                    ) {
                        WeekView(
                            events: sample,
                            activeTime: FactoryLogActiveTime(events: sample),
                            weekOffset: .constant(-1),
                            onSelectDay: { _ in }
                        )
                    }
                } else {
                    WeekView(
                        events: visibleEvents,
                        activeTime: activeTime,
                        weekOffset: $weekOffset,
                        onSelectDay: openDay
                    )
                }
            case .insights:
                if isFirstRun {
                    let sample = SampleWork.events(before: Date())
                    FirstRunPreview(
                        title: "The long view",
                        message: "Where your time goes over weeks and months, which projects carry the momentum, and every task you did in each one.",
                        onGetStarted: { screen = .today }
                    ) {
                        ActivityDashboardView(
                            events: sample,
                            dailyAggregates: [],
                            activeTime: FactoryLogActiveTime(events: sample),
                            selectedProjectPath: .constant(nil),
                            loadError: nil,
                            isLoading: false,
                            onSelectDay: { _ in }
                        )
                    }
                } else {
                    ActivityDashboardView(
                        events: visibleEvents,
                        dailyAggregates: visibleDailyAggregates,
                        activeTime: activeTime,
                        selectedProjectPath: $selectedProjectPath,
                        loadError: loadError,
                        isLoading: isLoading,
                        onSelectDay: openDay
                    )
                }
            }
        }
    }

    private func dayView(
        _ day: Date,
        backTitle: String? = nil,
        onBack: (() -> Void)? = nil,
        onShowYesterday: (() -> Void)? = nil
    ) -> DayView {
        DayView(
            events: visibleEvents,
            activeTime: activeTime,
            day: day,
            narratives: narratives,
            loadError: loadError,
            isLoading: isLoading,
            backTitle: backTitle,
            onBack: onBack,
            isFirstRun: isFirstRun,
            onGetStarted: { screen = .today },
            onShowYesterday: onShowYesterday,
            onCompleteTask: completeTask
        )
    }

    private func openDay(_ day: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        if calendar.isDateInToday(day) {
            screen = .today
        } else if calendar.isDateInYesterday(day) {
            screen = .yesterday
        } else {
            openedDay = day
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            Text(FactoryLogProduct.displayName)
                .font(.headline)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var screenShortcuts: some View {
        ZStack {
            ForEach(AppScreen.allCases) { screen in
                Button(screen.title) {
                    self.screen = screen
                    openedDay = nil
                }
                .keyboardShortcut(screen.shortcut, modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }

        do {
            let store = store
            let (snapshot, activeTime) = try await Task.detached {
                do {
                    try store.archiveStaleTasks()
                } catch EventStore.StoreError.storeContainsIssues {
                    // Load the readable records below so the UI can explain the issue.
                }
                let snapshot = try store.loadSnapshot()
                return (snapshot, FactoryLogActiveTime(events: snapshot.events))
            }.value
            guard generation == reloadGeneration else {
                return
            }
            ProjectPalette.assign(sessions: activeTime.sessions, excluding: hiddenProjects)
            events = snapshot.events
            dailyAggregates = snapshot.dailyAggregates
            self.activeTime = activeTime
            loadError = snapshot.issues.isEmpty
                ? nil
                : snapshot.issues.map(\.message).joined(separator: " ")
            hasLoaded = true
        } catch {
            guard generation == reloadGeneration else {
                return
            }
            loadError = error.localizedDescription
            hasLoaded = true
        }
    }

    @MainActor
    private func completeTask(_ task: FactoryLogTask, summary: String) async throws {
        guard task.status == .doing, let latestEvent = task.events.last else {
            return
        }

        let archiveEvent = FactoryLogEvent(
            taskID: task.taskID,
            kind: .archived,
            project: task.project,
            taskTitle: task.title,
            source: latestEvent.source,
            summary: summary
        )
        let store = store

        try await Task.detached {
            try store.appendValidated(archiveEvent)
        }.value

        await reload()
    }
}
