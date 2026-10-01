import SwiftUI
import FactoryLogCore

/// Projects kept out of every view. Hiding is a display preference: the event
/// log is append-only, so a hidden project's events stay on disk untouched.
struct HiddenProjects: RawRepresentable, Equatable {
    static let storageKey = "hiddenProjects"

    /// Names are kept beside paths so Settings can list hidden projects
    /// without loading the event log.
    private var namesByPath: [String: String]

    init() {
        namesByPath = [:]
    }

    init?(rawValue: String) {
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: Data(rawValue.utf8)) else {
            return nil
        }
        namesByPath = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(namesByPath) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    var isEmpty: Bool {
        namesByPath.isEmpty
    }

    var projects: [FactoryLogEvent.Project] {
        namesByPath
            .map { FactoryLogEvent.Project(name: $0.value, path: $0.key) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func contains(_ path: String) -> Bool {
        namesByPath[path] != nil || Self.isAgentConfiguration(path)
    }

    private static let agentConfigurationFolders = [".cursor", ".codex", ".claude", ".agents"].map {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: $0).path
    }

    /// An agent's own folder, where it edits its skills, rules and hooks. That
    /// isn't project work, so it never shows up, without anyone hiding it.
    static func isAgentConfiguration(_ path: String) -> Bool {
        agentConfigurationFolders.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    mutating func hide(_ project: FactoryLogEvent.Project) {
        namesByPath[project.path] = project.name
    }

    mutating func show(_ project: FactoryLogEvent.Project) {
        namesByPath[project.path] = nil
    }
}

extension View {
    /// Adds a right-click "Hide Project" action to any view representing a project.
    func hidesProjectOnRightClick(_ project: FactoryLogEvent.Project) -> some View {
        modifier(HideProjectMenu(project: project))
    }
}

private struct HideProjectMenu: ViewModifier {
    @AppStorage(HiddenProjects.storageKey) private var hiddenProjects = HiddenProjects()
    let project: FactoryLogEvent.Project

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Hide Project", systemImage: "eye.slash") {
                hiddenProjects.hide(project)
            }
        }
    }
}
