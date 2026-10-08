import AppKit
import Foundation
import FactoryLogCore

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
            codex: containsFactoryLogInstructions(at: home.appending(path: ".codex/AGENTS.md"))
                && CodexSandbox.allowsWritingLog,
            cursor: containsFactoryLogInstructions(
                at: home.appending(path: ".cursor/rules/factory-log.mdc")
            )
        )
    }

    private static func containsFactoryLogInstructions(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return contents.contains("factorylog start") || contents.contains("Record durable work in Work Tracebook") || contents.contains("Record durable work in Factory Log")
    }
}

/// Whether agents can run `factorylog`. Agents get their PATH from the user's
/// login shell, not from the app, so the answer comes from that shell.
enum CommandLinePath: Equatable {
    case checking
    case found
    case missing

    static func check() async -> CommandLinePath {
        await Task.detached {
            (try? LoginShell.run("command -v factorylog")) == nil ? CommandLinePath.missing : .found
        }.value
    }
}

/// Runs commands the way a coding agent does: in the user's login shell, with
/// the PATH it sets up.
enum LoginShell {
    struct CommandFailed: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static var path: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }

    static var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static var isZsh: Bool {
        name == "zsh"
    }

    /// Single-quotes a value for zsh, bash and fish alike.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    @discardableResult
    static func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // Start from the PATH launchd gives every app, so the answer comes from
        // the shell's own config, not from how Work Tracebook happened to be opened.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandFailed(message: failureMessage(errorData, status: process.terminationStatus))
        }
        return String(decoding: outputData, as: UTF8.self)
    }

    /// The CLI's own JSON error when there is one, otherwise the last line the
    /// shell printed, such as "command not found".
    private static func failureMessage(_ data: Data, status: Int32) -> String {
        struct ErrorOutput: Decodable {
            struct Failure: Decodable {
                let message: String
            }

            let error: Failure
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() {
            if let output = try? JSONDecoder().decode(ErrorOutput.self, from: Data(line.utf8)) {
                return output.error.message
            }
        }
        return lines.last ?? "The command exited with status \(status)."
    }
}

/// Codex runs commands in a sandbox that can only write inside the project, so
/// `factorylog` needs the log folder among Codex's writable roots.
enum CodexSandbox {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/config.toml", directoryHint: .notDirectory)
    }

    static var logFolder: String {
        EventStoreLocation.defaultURL.deletingLastPathComponent().path
    }

    static var allowsWritingLog: Bool {
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        return config.contains(logFolder) || config.contains("danger-full-access")
    }
}

struct AgentIntegrationInstaller {
    enum InstallError: Error, LocalizedError {
        case missingBundledFile(String)
        case codexSandboxNeedsEdit(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledFile(let name):
                "The app bundle does not contain \(name). Reinstall Work Tracebook."
            case .codexSandboxNeedsEdit(let folder):
                "Added the instructions, but Codex's sandbox can't write the log yet. In ~/.codex/config.toml, add \"\(folder)\" to writable_roots under [sandbox_workspace_write]."
            }
        }
    }

    static let pathLine = #"export PATH="$HOME/.local/bin:$PATH""#

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

    /// Puts `~/.local/bin` on the PATH of every zsh, including the
    /// non-interactive ones agents start, which don't read `~/.zshrc`.
    func addCommandLineToolToPath() throws {
        let destination = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".zshenv", directoryHint: .notDirectory)
        let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        guard !existing.contains(Self.pathLine) else { return }
        try append("# Lets coding agents run factorylog. Added by Work Tracebook.\n\(Self.pathLine)", to: destination)
    }

    /// Adds the instructions, and the log folder to Codex's sandbox. A config
    /// that already has a sandbox section is left for the user to edit.
    func connectCodex() throws {
        try installCodexInstructions()
        guard !CodexSandbox.allowsWritingLog else { return }

        let existing = (try? String(contentsOf: CodexSandbox.configURL, encoding: .utf8)) ?? ""
        guard !existing.contains("sandbox_workspace_write") else {
            throw InstallError.codexSandboxNeedsEdit(CodexSandbox.logFolder)
        }
        let folder = CodexSandbox.logFolder
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: "\"", with: #"\""#)
        try append("[sandbox_workspace_write]\nwritable_roots = [\"\(folder)\"]", to: CodexSandbox.configURL)
    }

    private func installCodexInstructions() throws {
        let template = try bundledText(name: "agent-instructions", extension: "md")
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
        let destination = directory.appending(path: "AGENTS.md", directoryHint: .notDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let startMarker = "<!-- factory-log-managed:start -->"
        let endMarker = "<!-- factory-log-managed:end -->"
        let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        guard !existing.contains(startMarker) else { return }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = "\(existing)\(separator)\n\(startMarker)\n\(template)\n\(endMarker)\n"
        try Data(updated.utf8).write(to: destination, options: .atomic)
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

    /// Starts and closes a task through the installed CLI, from the login
    /// shell, so it takes the same path an agent's report does.
    static func sendTestReport() async throws {
        let taskID = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let start = [
            "factorylog start --task-id \(taskID)",
            "--title 'Test report'",
            "--summary 'Sent a test report from Work Tracebook.'",
            "--project-name 'Work Tracebook'",
            "--project-path \(LoginShell.quoted(CodexSandbox.logFolder))"
        ].joined(separator: " ")
        let archive = "factorylog archive --task-id \(taskID) --summary 'The test report arrived, so agents can report their work.'"

        _ = try await Task.detached {
            try LoginShell.run("\(start) && \(archive)")
        }.value
    }

    /// Appends a block on its own lines. Appending in place, rather than
    /// rewriting the file, keeps a dotfile that's a symlink a symlink.
    private func append(_ block: String, to url: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(separator)\(block)\n".utf8))
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
