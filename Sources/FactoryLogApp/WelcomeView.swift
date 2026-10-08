import AppKit
import SwiftUI
import FactoryLogCore

/// The first thing a new install shows: what Work Tracebook does, and the three
/// steps that get the first report in. It gives way to the day on its own as
/// soon as that report arrives.
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("WELCOME TO WORK TRACEBOOK")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .tracking(1)

                        Text("See what your agents did for you")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                }

                Text("Coding agents write a one-line report each time they finish something. Work Tracebook turns those reports into a timeline of your day and your week, and shows where the time went, project by project.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SetupChecklist(showsWaitingStep: true)

                Label {
                    Text("Everything stays on this Mac, in `~/Library/Application Support/Factory Log`. Work Tracebook never reads your code, diffs or terminal output.")
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The setup steps with their live state. Each step turns green once it's done,
/// and its buttons do the work in place.
struct SetupChecklist: View {
    var showsWaitingStep = false

    @State private var setup = AgentSetupStatus.current
    @State private var path = CommandLinePath.checking
    @State private var isSendingTestReport = false
    @State private var message: String?
    @State private var error: String?

    private let installer = AgentIntegrationInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(
                number: 1,
                title: "Install the command-line tool",
                detail: commandLineDetail,
                isDone: setup.commandLineTool && !isOffPath
            ) {
                commandLineActions
            }

            Divider()

            step(
                number: 2,
                title: "Connect your coding agent",
                detail: "Adds a short instruction that asks the agent to report what it finished.",
                isDone: setup.hasAgentIntegration
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(setup.codex ? "Codex Connected" : "Connect Codex") {
                            perform("Connected Codex. New Codex sessions will report their work.") {
                                try installer.connectCodex()
                            }
                        }
                        .disabled(setup.codex)

                        Button(setup.cursor ? "Cursor Connected" : "Connect Cursor") {
                            perform("Installed the Work Tracebook rule for Cursor.") {
                                _ = try installer.installCursorRule()
                            }
                        }
                        .disabled(setup.cursor)
                    }

                    Button("Another agent? Copy the instructions") {
                        perform("Copied. Paste them into your agent's instructions file.") {
                            try installer.copyAgentInstructions()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if showsWaitingStep {
                Divider()

                step(
                    number: 3,
                    title: "Ask an agent to build something",
                    detail: "Agents report work that changes something, like a fix or a new feature, not answers to questions. The first report shows up here a second later, and this screen turns into your day.",
                    isDone: false
                ) {
                    if setup.isReady && path == .found {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for the first report…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Send a test report", action: sendTestReport)
                                .buttonStyle(.link)
                                .font(.caption)
                                .disabled(isSendingTestReport)
                        }
                    }
                }
            }

            if let message {
                Divider()
                Label {
                    Text(LocalizedStringKey(message))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.callout)
                .foregroundStyle(.green)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            if let error {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .dashboardCard(padding: 0)
        .task {
            path = await CommandLinePath.check()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var isOffPath: Bool {
        setup.commandLineTool && path == .missing
    }

    private var commandLineDetail: LocalizedStringKey {
        guard isOffPath else {
            return "Agents run `factorylog` to report their work. Work Tracebook puts it in `~/.local/bin`."
        }
        if LoginShell.isZsh {
            return "It's in `~/.local/bin`, but your shell doesn't look there, so agents can't run it. Add that folder to your PATH."
        }
        return "It's in `~/.local/bin`, but your shell doesn't look there, so agents can't run it. Add that folder to your PATH in your \(LoginShell.name) config, then check again."
    }

    @ViewBuilder
    private var commandLineActions: some View {
        if isOffPath {
            if LoginShell.isZsh {
                Button("Add to PATH") {
                    perform("Added `~/.local/bin` to your PATH in `~/.zshenv`. Restart any agent that's already running.") {
                        try installer.addCommandLineToolToPath()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Check Again", action: refresh)
            }
        } else {
            let install = Button(setup.commandLineTool ? "Reinstall" : "Install CLI") {
                perform("Installed `factorylog` in `~/.local/bin`.") {
                    _ = try installer.installCommandLineTool()
                }
            }
            if setup.commandLineTool {
                install
            } else {
                install.buttonStyle(.borderedProminent)
            }
        }
    }

    private func refresh() {
        setup = .current
        Task {
            path = await CommandLinePath.check()
        }
    }

    private func sendTestReport() {
        isSendingTestReport = true
        Task {
            do {
                try await AgentIntegrationInstaller.sendTestReport()
                message = "Sent a test report. It's in today's log."
                error = nil
            } catch {
                message = nil
                self.error = error.localizedDescription
            }
            isSendingTestReport = false
        }
    }

    private func step<Actions: View>(
        number: Int,
        title: String,
        detail: LocalizedStringKey,
        isDone: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func perform(_ successMessage: String, action: () throws -> Void) {
        do {
            try action()
            message = successMessage
            error = nil
        } catch {
            message = nil
            self.error = error.localizedDescription
        }
        refresh()
    }
}

/// A centered note for a screen with nothing to show yet.
struct EmptyStateCard<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)

            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .dashboardCard()
    }
}

/// A screen rendered with made-up work behind a short explanation, so a new
/// install shows what the screen will become instead of a blank page.
struct FirstRunPreview<Preview: View>: View {
    let title: String
    let message: String
    let onGetStarted: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        ZStack {
            preview
                .saturation(0.5)
                .opacity(0.4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("PREVIEW")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(1)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
            .padding(30)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        }
    }
}

/// Three weeks of believable, made-up agent work for the first-run previews.
/// None of it is written to the log.
enum SampleWork {
    private static let projects: [FactoryLogEvent.Project] = [
        .init(name: "storefront", path: "/Sample/storefront"),
        .init(name: "mobile-app", path: "/Sample/mobile-app"),
        .init(name: "docs-site", path: "/Sample/docs-site"),
        .init(name: "billing-api", path: "/Sample/billing-api")
    ]

    private static let titles = [
        "Add the checkout summary", "Fix the login redirect", "Write the onboarding guide",
        "Speed up the search index", "Add invoice exports", "Polish the settings screen"
    ]

    /// Sessions per weekday as (start hour, minutes, project index).
    private static let pattern: [[(Double, Double, Int)]] = [
        [(9, 110, 0), (13.5, 70, 2), (16, 50, 1)],
        [(8.5, 90, 1), (11, 45, 3), (14, 120, 0)],
        [(10, 60, 2), (12.5, 40, 0), (15, 95, 3)],
        [(9, 75, 0), (11.5, 50, 1), (14.5, 80, 0), (17, 30, 2)],
        [(9.5, 100, 3), (13, 60, 0)]
    ]

    static func events(before today: Date, days: Int = 21, calendar: Calendar = .current) -> [FactoryLogEvent] {
        var events: [FactoryLogEvent] = []
        for dayOffset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: today)) else {
                continue
            }
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            for (index, session) in pattern[weekday % pattern.count].enumerated() {
                let (startHour, minutes, projectIndex) = session
                let project = projects[(projectIndex + dayOffset / 7) % projects.count]
                let taskID = "sample-\(dayOffset)-\(index)"
                let title = titles[(dayOffset + index) % titles.count]
                let start = day.addingTimeInterval(startHour * 3_600)
                let updates = max(Int(minutes / 15), 1)
                for update in 0...updates {
                    events.append(
                        FactoryLogEvent(
                            id: "\(taskID)-\(update)",
                            taskID: taskID,
                            timestamp: start.addingTimeInterval(Double(update) * minutes * 60 / Double(updates)),
                            kind: update == 0 ? .started : (update == updates ? .archived : .reported),
                            project: project,
                            taskTitle: title,
                            source: .init(tool: .codex),
                            summary: "Made progress on \(title.lowercased())."
                        )
                    )
                }
            }
        }
        return events
    }
}
