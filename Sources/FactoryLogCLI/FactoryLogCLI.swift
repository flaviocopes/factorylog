import Darwin
import Foundation
import FactoryLogCore

@main
enum FactoryLogCLI {
    private struct SuccessOutput: Encodable {
        let ok = true
        let event: FactoryLogEvent
        let storePath: String
    }

    private struct FailureOutput: Encodable {
        struct Detail: Encodable {
            let code: String
            let message: String
        }

        let ok = false
        let error: Detail
    }

    private enum CLIError: Error {
        case invalidArguments(String)
        case invalidState(String)

        var code: String {
            switch self {
            case .invalidArguments:
                "invalid_arguments"
            case .invalidState:
                "invalid_state"
            }
        }

        var message: String {
            switch self {
            case .invalidArguments(let message), .invalidState(let message):
                message
            }
        }
    }

    private struct Options {
        private let values: [String: String]

        init(_ arguments: ArraySlice<String>, allowed: Set<String>) throws {
            let arguments = Array(arguments)
            var values: [String: String] = [:]
            var index = 0

            while index < arguments.count {
                let option = arguments[index]
                guard option.hasPrefix("--") else {
                    throw CLIError.invalidArguments("Unexpected argument '\(option)'. Options must use --name value.")
                }

                let name = String(option.dropFirst(2))
                guard allowed.contains(name) else {
                    throw CLIError.invalidArguments("Unknown option '--\(name)'.")
                }
                guard values[name] == nil else {
                    throw CLIError.invalidArguments("Option '--\(name)' was provided more than once.")
                }
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.invalidArguments("Option '--\(name)' requires a value.")
                }

                values[name] = arguments[index + 1]
                index += 2
            }

            self.values = values
        }

        func required(_ name: String) throws -> String {
            guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                throw CLIError.invalidArguments("Missing required option '--\(name)'.")
            }
            return value
        }

        func optional(_ name: String) throws -> String? {
            guard let value = values[name] else {
                return nil
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CLIError.invalidArguments("Option '--\(name)' cannot be empty.")
            }
            return trimmed
        }
    }

    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty || arguments.first == "help" || arguments.first == "--help" {
                print(usage)
                return
            }
            if arguments == ["version"] || arguments == ["--version"] {
                print("factorylog \(FactoryLogVersion.current)")
                return
            }

            let result = try run(arguments)
            try writeJSON(result, to: .standardOutput)
        } catch let error as CLIError {
            let output = FailureOutput(
                error: .init(code: error.code, message: error.message)
            )
            try? writeJSON(output, to: .standardError)
            exit(2)
        } catch {
            let output = FailureOutput(
                error: .init(code: "internal_error", message: error.localizedDescription)
            )
            try? writeJSON(output, to: .standardError)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws -> SuccessOutput {
        guard let command = arguments.first else {
            throw CLIError.invalidArguments("A command is required.")
        }

        let commonOptions: Set<String> = ["task-id", "summary", "source", "session-id", "store", "timestamp"]
        let options: Options
        switch command {
        case "start":
            options = try Options(
                arguments.dropFirst(),
                allowed: commonOptions.union(["project-name", "project-path", "title"])
            )
        case "report", "archive":
            options = try Options(arguments.dropFirst(), allowed: commonOptions)
        default:
            throw CLIError.invalidArguments("Unknown command '\(command)'. Use start, report, or archive.")
        }

        let store = try makeStore(options: options)
        let event: FactoryLogEvent
        switch command {
        case "start":
            event = try start(options: options, store: store)
        case "report":
            event = try update(kind: .reported, options: options, store: store)
        case "archive":
            event = try update(kind: .archived, options: options, store: store)
        default:
            preconditionFailure("Validated command was not handled.")
        }

        do {
            try store.appendValidated(event)
        } catch let error as EventStore.StoreError {
            throw CLIError.invalidState(error.localizedDescription)
        }
        return SuccessOutput(event: event, storePath: store.url.path)
    }

    private static func start(options: Options, store: EventStore) throws -> FactoryLogEvent {
        let title = try options.required("title")
        let summary = try options.required("summary")
        let projectPathInput = try options.optional("project-path")
            ?? FileManager.default.currentDirectoryPath

        guard NSString(string: projectPathInput).isAbsolutePath else {
            throw CLIError.invalidArguments("Option '--project-path' must be an absolute path.")
        }

        let projectPath = URL(fileURLWithPath: projectPathInput).standardizedFileURL.path
        let defaultProjectName = URL(fileURLWithPath: projectPath).lastPathComponent
        let projectName = try options.optional("project-name") ?? defaultProjectName
        guard !projectName.isEmpty else {
            throw CLIError.invalidArguments("Option '--project-name' is required for the filesystem root.")
        }

        let taskID = try options.optional("task-id") ?? makeTaskID()
        return FactoryLogEvent(
            taskID: taskID,
            timestamp: try makeTimestamp(options: options),
            kind: .started,
            project: .init(name: projectName, path: projectPath),
            taskTitle: title,
            source: try makeSource(options: options, fallback: nil),
            summary: summary
        )
    }

    private static func update(
        kind: FactoryLogEvent.Kind,
        options: Options,
        store: EventStore
    ) throws -> FactoryLogEvent {
        let taskID = try options.required("task-id")
        let summary = try options.required("summary")
        let history = try store.loadEvents().filter { $0.taskID == taskID }

        guard let started = history.first(where: { $0.kind == .started }) else {
            throw CLIError.invalidState("Task '\(taskID)' has not been started.")
        }
        guard !history.contains(where: { $0.kind == .archived }) else {
            throw CLIError.invalidState("Task '\(taskID)' is already archived.")
        }

        return FactoryLogEvent(
            taskID: taskID,
            timestamp: try makeTimestamp(options: options),
            kind: kind,
            project: started.project,
            taskTitle: started.taskTitle,
            source: try makeSource(options: options, fallback: history.last?.source),
            summary: summary
        )
    }

    private static func makeSource(
        options: Options,
        fallback: FactoryLogEvent.Source?
    ) throws -> FactoryLogEvent.Source {
        let tool: FactoryLogEvent.Source.Tool
        if let source = try options.optional("source") {
            let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            guard source.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
                throw CLIError.invalidArguments(
                    "Option '--source' may contain only letters, numbers, hyphens, underscores, and periods."
                )
            }
            tool = .init(rawValue: source)
        } else {
            tool = fallback?.tool ?? .other
        }

        let environmentSessionID = tool == .codex
            ? ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
            : nil
        let fallbackSessionID = fallback?.tool == tool ? fallback?.sessionID : nil
        let sessionID = try options.optional("session-id")
            ?? fallbackSessionID
            ?? environmentSessionID
        return .init(tool: tool, sessionID: sessionID)
    }

    private static func makeStore(options: Options) throws -> EventStore {
        guard let path = try options.optional("store") else {
            return EventStore()
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        return EventStore(url: URL(fileURLWithPath: expandedPath).standardizedFileURL)
    }

    private static func makeTimestamp(options: Options) throws -> Date {
        guard let value = try options.optional("timestamp") else {
            return Date()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw CLIError.invalidArguments(
                "Option '--timestamp' must be an RFC 3339 timestamp with a time zone."
            )
        }
        return date
    }

    private static func makeTaskID() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "task_\(uuid)"
    }

    private static func writeJSON<T: Encodable>(_ value: T, to handle: FileHandle) throws {
        var data = try FactoryLogJSON.makeEncoder().encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static let usage = """
    Factory Log records short, agent-written task updates.

    Usage:
      factorylog start --title <title> --summary <summary> [options]
      factorylog report --task-id <id> --summary <summary> [options]
      factorylog archive --task-id <id> --summary <summary> [options]

    Start options:
      --project-path <path>  Absolute project path. Defaults to the current directory.
      --project-name <name>  Project name. Defaults to the project directory name.
      --task-id <id>         Stable task ID. Factory Log generates one when omitted.

    Shared options:
      --source <tool>        Source identifier, such as codex or cursor. Defaults to other.
      --session-id <id>      Optional source session ID. Codex uses CODEX_THREAD_ID when omitted.
      --store <path>         Event file. Defaults to the Factory Log application support folder.
      --timestamp <time>     RFC 3339 event time. Defaults to the current time.

    Successful commands print one JSON object to stdout. Errors print JSON to stderr.
    """
}
