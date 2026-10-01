import AppKit
import SwiftUI
import FactoryLogCore

/// "What I did" for one day: how long, when, on which projects, and every task.
struct DayView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case log = "Log"

        var id: String {
            rawValue
        }
    }

    let events: [FactoryLogEvent]
    let activeTime: FactoryLogActiveTime
    let day: Date
    let narratives: DayNarratives
    let loadError: String?
    let isLoading: Bool
    var backTitle: String?
    var onBack: (() -> Void)?
    /// True before the log has any reports at all.
    var isFirstRun = false
    var onGetStarted: (() -> Void)?
    var onShowYesterday: (() -> Void)?
    let onCompleteTask: (FactoryLogTask, String) async throws -> Void

    /// Finished days open as a per-project recap; today opens as the live log.
    @State private var tab: Tab = .log
    @State private var statusFilter: FactoryLogTask.Status?
    @State private var selectedProjectPath: String?

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        let model = DayModel(events: events, activeTime: activeTime, day: day, projectPath: selectedProjectPath)

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
            } else if isFirstRun {
                firstRunPreview
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(model)

                        if model.allTasks.isEmpty {
                            emptyState
                        } else {
                            statTiles(model)
                            timelineCard(model)
                            workSection(model)
                        }
                    }
                    .frame(maxWidth: 1_100, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(shortcuts(hasTasks: !model.allTasks.isEmpty))
        .onChange(of: day, initial: true) {
            statusFilter = nil
            selectedProjectPath = nil
            tab = isToday ? .log : .summary
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .summary {
                statusFilter = nil
            }
        }
    }

    // MARK: Header

    private func header(_ model: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onBack, let backTitle {
                Button(action: onBack) {
                    Label(backTitle, systemImage: "chevron.left")
                }
                .buttonStyle(.link)
                .font(.callout.weight(.medium))
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .tracking(1)

                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(subtitle(model))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.allTasks.isEmpty)
            }
        }
    }

    private var eyebrow: String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if isToday {
            return "TODAY · \(date.uppercased())"
        }
        if Calendar.current.isDateInYesterday(day) {
            return "YESTERDAY · \(date.uppercased())"
        }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()).uppercased()
    }

    private var title: String {
        if isToday {
            return "What I did today"
        }
        if Calendar.current.isDateInYesterday(day) {
            return "What I did yesterday"
        }
        return "What I did on \(day.formatted(.dateTime.weekday(.wide)))"
    }

    private func subtitle(_ model: DayModel) -> String {
        guard !model.allTasks.isEmpty else {
            return isToday ? "No reports yet." : "No agent reports on this day."
        }
        let projectCount = model.secondsByProject.count
        let projectWord = projectCount == 1 ? "project" : "projects"
        let taskWord = model.allTasks.count == 1 ? "task" : "tasks"
        var text = "\(ActiveTimeFormat.text(model.totalSeconds)) of active work across \(projectCount) \(projectWord) and \(model.allTasks.count) \(taskWord)."
        let open = model.allTasks.count { $0.status == .doing }
        if isToday, open > 0 {
            text += " \(open) still open."
        }
        return text
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if isToday {
                EmptyStateCard(
                    symbol: "sun.horizon.fill",
                    title: "Nothing logged yet today",
                    message: "When an agent finishes something, its report lands here a second later, with the project it belongs to and the time it took."
                ) {
                    if let onShowYesterday {
                        Button("See What I Did Yesterday", action: onShowYesterday)
                    }
                }
            } else {
                EmptyStateCard(
                    symbol: "moon.zzz.fill",
                    title: "A quiet day",
                    message: "No agent reported any work on this day. The Week view shows which days have activity."
                ) {
                    EmptyView()
                }
            }

            if !AgentSetupStatus.current.isReady {
                SetupChecklist()
            }
        }
    }

    /// Yesterday on a new install: the recap the screen will show, drawn with
    /// sample work.
    private var firstRunPreview: some View {
        let sample = SampleWork.events(before: Date())
        let model = DayModel(events: sample, activeTime: FactoryLogActiveTime(events: sample), day: day, projectPath: nil)

        return FirstRunPreview(
            title: "Yesterday's recap lives here",
            message: "Each morning, see how long you worked the day before, when, on which projects, and a one-line summary of each.",
            onGetStarted: { onGetStarted?() }
        ) {
            VStack(alignment: .leading, spacing: 22) {
                header(model)
                statTiles(model)
                timelineCard(model)
            }
            .frame(maxWidth: 1_100, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Stats

    private func statTiles(_ model: DayModel) -> some View {
        let open = model.allTasks.count { $0.status == .doing }
        let done = model.allTasks.count - open

        return HStack(spacing: 12) {
            DayStatTile(
                value: ActiveTimeFormat.text(model.totalSeconds),
                label: "Active time",
                symbol: "clock.fill",
                tint: .blue
            )
            .help(ActiveTimeFormat.explanation)

            DayStatTile(
                value: model.secondsByProject.count.formatted(),
                label: model.secondsByProject.count == 1 ? "Project" : "Projects",
                symbol: "folder.fill",
                tint: .purple
            )

            DayStatTile(
                value: model.allTasks.count.formatted(),
                label: model.allTasks.count == 1 ? "Task" : "Tasks",
                symbol: "checklist",
                tint: .green
            )

            if isToday {
                DayStatTile(value: open.formatted(), label: "Still open", symbol: "circle.dotted", tint: .orange)
            } else {
                DayStatTile(value: done.formatted(), label: "Completed", symbol: "checkmark.seal.fill", tint: .orange)
            }
        }
    }

    // MARK: Timeline

    private func timelineCard(_ model: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What you worked on")
                    .font(.headline)

                Spacer()

                if let first = model.segments.map(\.start).min(), let last = model.segments.map(\.end).max() {
                    Text("\(first.formatted(.dateTime.hour().minute())) – \(last.formatted(.dateTime.hour().minute()))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if model.segments.isEmpty {
                Text("No timed work on this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                DayTimelineChart(
                    segments: model.segments,
                    day: model.interval,
                    secondsByProject: model.secondsByProject,
                    showsNow: isToday,
                    selectedProjectPath: $selectedProjectPath
                )
            }
        }
        .dashboardCard()
    }

    // MARK: Work

    private func workSection(_ model: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(tab == .summary ? "By project" : "Every task")
                    .font(.headline)

                if let path = selectedProjectPath,
                   let project = model.allSummaries.first(where: { $0.project.path == path })?.project {
                    projectChip(project)
                }

                Spacer()

                if tab == .log {
                    statusFilterButton(.doing, count: model.tasks.count { $0.status == .doing })
                    statusFilterButton(.done, count: model.tasks.count { $0.status == .done })
                }
            }

            if tab == .summary {
                DaySummaryView(
                    summaries: model.summaries,
                    day: day,
                    narratives: narratives,
                    secondsByProject: model.secondsByProject
                ) { summary in
                    selectedProjectPath = summary.project.path
                    tab = .log
                }
            } else {
                let visibleTasks = statusFilter.map { filter in model.tasks.filter { $0.status == filter } } ?? model.tasks
                if visibleTasks.isEmpty, let statusFilter {
                    ContentUnavailableView(
                        "No \(statusLabel(for: statusFilter)) tasks",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Click the selected filter again to show all tasks.")
                    )
                    .frame(minHeight: 200)
                } else if isToday {
                    // Only today's labels drift as time passes; a finished day
                    // needs no ticking clock.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        log(visibleTasks, now: context.date)
                    }
                } else {
                    log(visibleTasks, now: .now)
                }
            }
        }
    }

    private func projectChip(_ project: FactoryLogEvent.Project) -> some View {
        let color = DashboardSnapshot.color(for: project.path)
        return Button {
            selectedProjectPath = nil
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(project.name)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show all projects")
    }

    private func log(_ tasks: [FactoryLogTask], now: Date) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(loggedTasks(tasks, now: now)) { row in
                TaskRow(
                    task: row.task,
                    event: row.event,
                    timeLabel: row.timeLabel,
                    onCompleteTask: onCompleteTask
                )
            }
        }
    }

    /// Each task touched that day appears once, ordered by its latest update.
    /// The card carries that update's summary while status comes from the whole
    /// task thread, so an archived task reads as done without repeating its
    /// started and reported events as separate cards.
    private func loggedTasks(_ tasks: [FactoryLogTask], now: Date) -> [LoggedTask] {
        var rows: [LoggedTask] = []
        var shownLabel: String?

        for task in tasks {
            guard let event = task.events(on: day).last(where: { !$0.isAutomaticArchive }) ?? task.events(on: day).last else {
                continue
            }
            let label = TimeLabel.text(for: event.timestamp, now: now)
            rows.append(LoggedTask(task: task, event: event, timeLabel: label == shownLabel ? nil : label))
            shownLabel = label
        }
        return rows
    }

    private func statusFilterButton(_ status: FactoryLogTask.Status, count: Int) -> some View {
        let label = statusLabel(for: status)
        let isSelected = statusFilter == status

        return Button {
            statusFilter = statusFilter == status ? nil : status
            tab = .log
        } label: {
            StatusCountBadge(
                count: count,
                label: label,
                emphasized: status == .doing && count > 0,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Show all tasks" : "Show only \(label.lowercased()) tasks")
        .accessibilityLabel("\(label) tasks, \(count)")
        .accessibilityValue(isSelected ? "Filtered" : "Not filtered")
    }

    private func statusLabel(for status: FactoryLogTask.Status) -> String {
        status == .doing ? "Doing" : "Done"
    }

    // MARK: Keyboard

    /// Invisible buttons carry the window's keyboard shortcuts: the arrows walk
    /// between the two views, and Escape backs out of a single project, then
    /// out of a day opened from another view.
    private func shortcuts(hasTasks: Bool) -> some View {
        ZStack {
            Button("Summary") {
                tab = .summary
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!hasTasks || tab == .summary)

            Button("Log") {
                tab = .log
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!hasTasks || tab == .log)

            Button("Back") {
                if selectedProjectPath != nil {
                    selectedProjectPath = nil
                    tab = isToday ? .log : .summary
                } else {
                    onBack?()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(selectedProjectPath == nil && onBack == nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything the day view derives from the log, computed once per render.
private struct DayModel {
    let interval: DateInterval
    /// Every task touched that day, across all projects.
    let allTasks: [FactoryLogTask]
    /// The tasks shown, narrowed to the selected project.
    let tasks: [FactoryLogTask]
    let allSummaries: [FactoryLogProjectSummary]
    let summaries: [FactoryLogProjectSummary]
    let segments: [TimelineSegment]
    let secondsByProject: [String: TimeInterval]
    let totalSeconds: TimeInterval

    init(events: [FactoryLogEvent], activeTime: FactoryLogActiveTime, day: Date, projectPath: String?) {
        let calendar = Calendar.current
        interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)

        let history = FactoryLogHistory(events: events)
        let dayEvents = history.activity(on: day).filter { !$0.isAutomaticArchive }
        let secondsByProject = Dictionary(grouping: dayEvents, by: \.project.path)
            .mapValues { activeTime.seconds(for: $0) }
        self.secondsByProject = secondsByProject
        totalSeconds = secondsByProject.values.reduce(0, +)

        allTasks = history.tasks(activeOn: day)
        // Biggest share of the day first, matching the timeline's lanes.
        allSummaries = history.projectSummaries(on: day).sorted {
            (secondsByProject[$0.project.path] ?? 0) > (secondsByProject[$1.project.path] ?? 0)
        }
        if let projectPath {
            tasks = allTasks.filter { $0.project.path == projectPath }
            summaries = allSummaries.filter { $0.project.path == projectPath }
        } else {
            tasks = allTasks
            summaries = allSummaries
        }

        let visiblePaths = Set(dayEvents.map(\.project.path))
        segments = TimelineSegment.clip(
            activeTime.sessions(overlapping: interval).filter { visiblePaths.contains($0.project.path) },
            to: interval
        )
    }
}

private struct DayStatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .dashboardCard(padding: 14)
    }
}

private struct LoggedTask: Identifiable {
    let task: FactoryLogTask
    let event: FactoryLogEvent
    /// `nil` when the row above already carries this time.
    let timeLabel: String?

    var id: FactoryLogTask.ID {
        task.id
    }
}

/// One task represented by its latest update on the selected day.
private struct TaskRow: View {
    let task: FactoryLogTask
    let event: FactoryLogEvent
    let timeLabel: String?
    let onCompleteTask: (FactoryLogTask, String) async throws -> Void

    @State private var isHoveringStatus = false
    @State private var isHoveringRow = false
    @State private var isShowingCompletionSheet = false

    private var projectColor: Color {
        DashboardSnapshot.color(for: task.project.path)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.headline)

                    if task.status == .doing {
                        doingBadge
                    }
                }

                Text(event.summary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Circle()
                        .fill(projectColor)
                        .frame(width: 7, height: 7)
                    Text(event.project.name)
                    Text("·")
                    Text(event.source.tool.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingContent
        }
        .padding(.vertical, 15)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .background {
            ZStack(alignment: .leading) {
                Color(nsColor: .textBackgroundColor)
                projectColor
                    .frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .onHover { isHoveringRow = $0 }
        .sheet(isPresented: $isShowingCompletionSheet) {
            TaskCompletionSheet(task: task, onCompleteTask: onCompleteTask)
        }
    }

    private var trailingContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let codexThreadURL = task.codexThreadURL {
                Button {
                    NSWorkspace.shared.open(codexThreadURL)
                } label: {
                    HStack(spacing: 5) {
                        Text("Open in Codex")
                            .opacity(isHoveringRow ? 1 : 0)
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .animation(.easeOut(duration: 0.12), value: isHoveringRow)
                .help("Open this task in Codex")
                .accessibilityLabel("Open \(task.title) in Codex")
            }

            Text(timeLabel ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var doingBadge: some View {
        Button {
            isShowingCompletionSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(isHoveringStatus ? "Mark Done" : "Doing")

                if isHoveringStatus {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(isHoveringStatus ? Color.white : Color.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            isHoveringStatus ? Color.accentColor : Color.accentColor.opacity(0.10),
            in: Capsule()
        )
        .onHover { isHoveringStatus = $0 }
        .animation(.easeOut(duration: 0.12), value: isHoveringStatus)
        .help("Mark this task as Done")
        .accessibilityElement()
        .accessibilityLabel("Mark \(task.title) as Done")
        .accessibilityHint("Opens a form for the task's final outcome")
    }
}

private struct TaskCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: FactoryLogTask
    let onCompleteTask: (FactoryLogTask, String) async throws -> Void

    @State private var summary: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        task: FactoryLogTask,
        onCompleteTask: @escaping (FactoryLogTask, String) async throws -> Void
    ) {
        self.task = task
        self.onCompleteTask = onCompleteTask

        let latestEvent = task.events.last
        let suggestedSummary = latestEvent?.kind == .reported ? latestEvent?.summary ?? "" : ""
        _summary = State(initialValue: suggestedSummary)
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mark as Done")
                    .font(.title2.weight(.semibold))

                Text(task.title)
                    .font(.headline)

                Text("Add the final outcome to close this task. Its earlier updates remain unchanged.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Final outcome", text: $summary, axis: .vertical)
                .lineLimit(2...5)

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

                Button("Mark Done") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedSummary.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard !trimmedSummary.isEmpty else {
            return
        }

        isSaving = true
        saveError = nil

        Task {
            do {
                try await onCompleteTask(task, trimmedSummary)
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct StatusCountBadge: View {
    let count: Int
    let label: String
    let emphasized: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(emphasized ? Color.accentColor : Color.secondary.opacity(0.55))
                .frame(width: 6, height: 6)

            Text("\(count) \(label)")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(emphasized || isSelected ? Color.primary : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}
