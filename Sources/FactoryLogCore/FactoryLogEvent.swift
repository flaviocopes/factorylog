import Foundation

public struct FactoryLogEvent: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case started = "task.started"
        case reported = "task.reported"
        case archived = "task.archived"
    }

    public struct Project: Codable, Equatable, Sendable {
        public let name: String
        public let path: String

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    public struct Source: Codable, Equatable, Sendable {
        public struct Tool: RawRepresentable, Codable, CaseIterable, Hashable, Sendable {
            public static let codex = Tool(rawValue: "codex")
            public static let cursor = Tool(rawValue: "cursor")
            public static let other = Tool(rawValue: "other")
            public static let allCases: [Tool] = [.codex, .cursor, .other]

            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                rawValue = try container.decode(String.self)
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }

        public let tool: Tool
        public let sessionID: String?

        public init(tool: Tool, sessionID: String? = nil) {
            self.tool = tool
            self.sessionID = sessionID
        }
    }

    public let schemaVersion: Int
    public let id: String
    public let taskID: String
    public let timestamp: Date
    public let kind: Kind
    public let project: Project
    public let taskTitle: String
    public let source: Source
    public let summary: String

    public init(
        schemaVersion: Int = FactoryLogEvent.currentSchemaVersion,
        id: String = UUID().uuidString.lowercased(),
        taskID: String,
        timestamp: Date = Date(),
        kind: Kind,
        project: Project,
        taskTitle: String,
        source: Source,
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        self.kind = kind
        self.project = project
        self.taskTitle = taskTitle
        self.source = source
        self.summary = summary
    }

    /// The archive Work Tracebook appends on its own a day after a task started.
    /// It closes the task but records no work.
    public var isAutomaticArchive: Bool {
        kind == .archived && summary == EventStore.automaticArchiveSummary
    }
}
