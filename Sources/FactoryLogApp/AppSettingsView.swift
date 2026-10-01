import AppKit
import SwiftUI
import FactoryLogCore

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appearance"

    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    static let storageKey = "detailedHistoryRetention"

    case thirtyDays = "30"
    case ninetyDays = "90"
    case oneEightyDays = "180"
    case oneYear = "365"
    case forever

    var id: String { rawValue }

    var days: Int? {
        Int(rawValue)
    }

    var label: String {
        switch self {
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .oneEightyDays: "180 days"
        case .oneYear: "1 year"
        case .forever: "Forever"
        }
    }
}

struct AgentSetupStatus {
    let commandLineTool: Bool
    let codex: Bool
    let cursor: Bool

    var hasAgentIntegration: Bool {
        codex || cursor
    }

    var isReady: Bool {
        commandLineTool && hasAgentIntegration
    }

    var setupMessage: String {
        if !commandLineTool {
            return "Install the Factory Log command-line tool to receive agent reports."
        }
        return "Connect Codex or Cursor to start receiving agent reports."
    }

    static var current: AgentSetupStatus {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let commandPaths = [
            home.appending(path: ".local/bin/factorylog").path,
            "/usr/local/bin/factorylog",
            "/opt/homebrew/bin/factorylog"
        ]

        return AgentSetupStatus(
            commandLineTool: commandPaths.contains(where: fileManager.isExecutableFile(atPath:)),
            codex: containsFactoryLogInstructions(
                at: home.appending(path: ".codex/AGENTS.md")
            ),
            cursor: containsFactoryLogInstructions(
                at: home.appending(path: ".cursor/rules/factory-log.mdc")
            )
        )
    }

    private static func containsFactoryLogInstructions(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return contents.contains("factorylog start") || contents.contains("Record durable work in Factory Log")
    }
}

struct AgentIntegrationInstaller {
    enum InstallError: Error, LocalizedError {
        case missingBundledFile(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledFile(let name):
                "The app bundle does not contain \(name). Reinstall Factory Log."
            }
        }
    }

    private let fileManager = FileManager.default

    func installCommandLineTool() throws -> URL {
        let source = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/factorylog", directoryHint: .notDirectory)
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw InstallError.missingBundledFile("the command-line tool")
        }

        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".local/bin", directoryHint: .isDirectory)
        let destination = directory.appending(path: "factorylog", directoryHint: .notDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    func installCodexInstructions() throws -> URL {
        let template = try bundledText(name: "agent-instructions", extension: "md")
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
        let destination = directory.appending(path: "AGENTS.md", directoryHint: .notDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let startMarker = "<!-- factory-log-managed:start -->"
        let endMarker = "<!-- factory-log-managed:end -->"
        let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        guard !existing.contains(startMarker) else { return destination }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = "\(existing)\(separator)\n\(startMarker)\n\(template)\n\(endMarker)\n"
        try Data(updated.utf8).write(to: destination, options: .atomic)
        return destination
    }

    func installCursorRule() throws -> URL {
        let template = try bundledText(name: "cursor-factory-log", extension: "mdc")
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".cursor/rules", directoryHint: .isDirectory)
        let destination = directory.appending(path: "factory-log.mdc", directoryHint: .notDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(template.utf8).write(to: destination, options: .atomic)
        return destination
    }

    func copyAgentInstructions() throws {
        let template = try bundledText(name: "agent-instructions", extension: "md")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(template, forType: .string)
    }

    private func bundledText(name: String, extension fileExtension: String) throws -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Integrations"
        ) else {
            throw InstallError.missingBundledFile("\(name).\(fileExtension)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct AppSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(HistoryRetention.storageKey) private var historyRetention = HistoryRetention.thirtyDays.rawValue
    @AppStorage(HiddenProjects.storageKey) private var hiddenProjects = HiddenProjects()
    @State private var setup = AgentSetupStatus.current
    @State private var setupMessage: String?
    @State private var setupError: String?
    @State private var storageUsage: EventStore.StorageUsage?
    @State private var compactionPreview: EventStore.CompactionPreview?
    @State private var historyMessage: String?
    @State private var historyError: String?
    @State private var isPurgingHistory = false
    @State private var isShowingPurgeConfirmation = false
    @State private var historyRefreshGeneration = 0

    private let store = EventStore()
    private let installer = AgentIntegrationInstaller()

    var body: some View {
        Form {
            Section("Log location") {
                LabeledContent("Event log") {
                    Text(abbreviatedStorePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Show in Finder") {
                    revealEventLog()
                }
            }

            Section("History & storage") {
                Picker("Detailed history", selection: $historyRetention) {
                    ForEach(HistoryRetention.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }

                if let storageUsage {
                    LabeledContent("Detailed log") {
                        Text("\(storageUsage.detailedEventCount.formatted()) updates · \(format(bytes: storageUsage.detailedBytes))")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Activity summaries") {
                        Text("\(storageUsage.aggregateCount.formatted()) rows · \(format(bytes: storageUsage.aggregateBytes))")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Total space") {
                        Text(format(bytes: storageUsage.totalBytes))
                            .fontWeight(.medium)
                    }
                } else {
                    ProgressView("Measuring storage…")
                        .controlSize(.small)
                }

                Button(purgeButtonTitle, role: .destructive) {
                    isShowingPurgeConfirmation = true
                }
                .disabled(
                    isPurgingHistory
                        || selectedRetention.days == nil
                        || (compactionPreview?.removableEventCount ?? 0) == 0
                )

                if let compactionPreview, selectedRetention.days != nil {
                    Text(compactionDescription(compactionPreview))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedRetention == .forever {
                    Text("Detailed history is kept indefinitely. Choose a retention period to make older detail eligible for purging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Purging preserves daily and project activity totals. All history for open tasks, plus the start and final outcome of completed tasks, remains available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Nothing is removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let historyMessage {
                    Text(historyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let historyError {
                    Text(historyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Hidden projects") {
                if hiddenProjects.isEmpty {
                    Text("Right-click a project to hide it. Its history stays in the log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hiddenProjects.projects, id: \.path) { project in
                        LabeledContent {
                            Button("Show") {
                                hiddenProjects.show(project)
                            }
                        } label: {
                            Text(project.name)
                            Text(NSString(string: project.path).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Integrations") {
                integrationRow(
                    "Command-line tool",
                    detail: "Receives reports from coding agents",
                    isConfigured: setup.commandLineTool
                )
                integrationRow(
                    "Codex",
                    detail: "Instructions in ~/.codex/AGENTS.md",
                    isConfigured: setup.codex
                )
                integrationRow(
                    "Cursor",
                    detail: "Rule in ~/.cursor/rules/factory-log.mdc",
                    isConfigured: setup.cursor
                )

                if !setup.isReady {
                    Text("Install the command-line tool, then connect at least one coding agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(setup.commandLineTool ? "Reinstall CLI" : "Install CLI") {
                        performSetup("Installed the CLI in ~/.local/bin.") {
                            _ = try installer.installCommandLineTool()
                        }
                    }
                    Button(setup.codex ? "Codex Connected" : "Connect Codex") {
                        performSetup("Added Factory Log instructions to ~/.codex/AGENTS.md.") {
                            _ = try installer.installCodexInstructions()
                        }
                    }
                    .disabled(setup.codex)
                    Button(setup.cursor ? "Cursor Connected" : "Connect Cursor") {
                        performSetup("Installed the Factory Log Cursor rule.") {
                            _ = try installer.installCursorRule()
                        }
                    }
                    .disabled(setup.cursor)
                }

                Button("Copy instructions for another agent") {
                    performSetup("Copied the agent instructions.") {
                        try installer.copyAgentInstructions()
                    }
                }

                if let setupMessage {
                    Text(setupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let setupError {
                    Text(setupError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

        }
        .formStyle(.grouped)
        .frame(width: 620, height: 720)
        .onAppear {
            setup = .current
            refreshStorageInfo()
        }
        .onChange(of: historyRetention) {
            historyMessage = nil
            historyError = nil
            refreshStorageInfo()
        }
        .confirmationDialog(
            "Purge old detailed history?",
            isPresented: $isShowingPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button(purgeButtonTitle, role: .destructive) {
                purgeHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(purgeConfirmationMessage)
        }
    }

    private var selectedRetention: HistoryRetention {
        HistoryRetention(rawValue: historyRetention) ?? .thirtyDays
    }

    private var purgeButtonTitle: String {
        guard let days = selectedRetention.days else {
            return "Purge old detailed history…"
        }
        return "Purge details older than \(days) days…"
    }

    private var purgeConfirmationMessage: String {
        let count = compactionPreview?.removableEventCount ?? 0
        return "This removes \(count.formatted()) detailed updates. Activity totals and essential task records will be kept. This cannot be undone."
    }

    private var abbreviatedStorePath: String {
        NSString(string: store.url.path).abbreviatingWithTildeInPath
    }

    private func format(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func compactionDescription(_ preview: EventStore.CompactionPreview) -> String {
        if preview.removableEventCount == 0 {
            return "No detailed updates are old enough to purge."
        }
        let protected = preview.protectedEventCount
        let suffix = protected == 0
            ? ""
            : " \(protected.formatted()) older essential updates will remain."
        return "\(preview.removableEventCount.formatted()) detailed updates can be purged.\(suffix)"
    }

    private func refreshStorageInfo() {
        historyRefreshGeneration += 1
        let generation = historyRefreshGeneration
        let retentionRawValue = historyRetention
        let days = selectedRetention.days
        compactionPreview = nil

        Task {
            do {
                let store = store
                let result = try await Task.detached {
                    let usage = try store.storageUsage()
                    let preview = try days.map {
                        try store.compactionPreview(retainingDays: $0)
                    }
                    return (usage, preview)
                }.value
                guard generation == historyRefreshGeneration,
                      retentionRawValue == historyRetention else {
                    return
                }
                storageUsage = result.0
                compactionPreview = result.1
            } catch {
                guard generation == historyRefreshGeneration else { return }
                historyError = error.localizedDescription
            }
        }
    }

    private func purgeHistory() {
        guard let days = selectedRetention.days else { return }
        isPurgingHistory = true
        historyMessage = nil
        historyError = nil

        Task {
            do {
                let store = store
                let result = try await Task.detached {
                    try store.compact(retainingDays: days)
                }.value
                historyMessage = result.removedEventCount == 0
                    ? "Nothing needed purging."
                    : "Purged \(result.removedEventCount.formatted()) detailed updates. Storage now uses \(format(bytes: result.bytesAfter)); \(format(bytes: result.bytesFreed)) reclaimed."
                refreshStorageInfo()
            } catch {
                historyError = error.localizedDescription
            }
            isPurgingHistory = false
        }
    }

    private func integrationRow(_ title: String, detail: String, isConfigured: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isConfigured ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isConfigured ? "Configured" : "Not configured")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func revealEventLog() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: store.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([store.url])
        } else {
            NSWorkspace.shared.open(store.url.deletingLastPathComponent())
        }
    }

    private func performSetup(_ successMessage: String, action: () throws -> Void) {
        do {
            try action()
            setup = .current
            setupMessage = successMessage
            setupError = nil
        } catch {
            setupMessage = nil
            setupError = error.localizedDescription
        }
    }
}
