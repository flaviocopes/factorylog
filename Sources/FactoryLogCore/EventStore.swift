import Darwin
import Foundation

public struct EventStore: Sendable {
    public static let automaticArchiveInterval: TimeInterval = 24 * 60 * 60
    public static let automaticArchiveSummary = "Automatically marked Done 24 hours after the task started."

    public enum StoreError: Error, Equatable, LocalizedError {
        case invalidEvent(line: Int)
        case unsupportedSchemaVersion(line: Int, version: Int)
        case taskAlreadyExists(String)
        case taskNotStarted(String)
        case taskAlreadyArchived(String)
        case taskMetadataMismatch(String)
        case storeContainsIssues(lines: [Int])
        case retentionTooShort(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidEvent(let line):
                "The event log contains invalid JSON on line \(line)."
            case .unsupportedSchemaVersion(let line, let version):
                "The event log uses unsupported schema version \(version) on line \(line)."
            case .taskAlreadyExists(let taskID):
                "Task '\(taskID)' already exists."
            case .taskNotStarted(let taskID):
                "Task '\(taskID)' has not been started."
            case .taskAlreadyArchived(let taskID):
                "Task '\(taskID)' is already archived."
            case .taskMetadataMismatch(let taskID):
                "Task '\(taskID)' does not match its original project or title."
            case .storeContainsIssues(let lines):
                "The event log must be repaired before it can be changed. Problem lines: \(lines.map(String.init).joined(separator: ", "))."
            case .retentionTooShort(let days):
                "Detailed history retention must be at least 30 days, not \(days)."
            }
        }
    }

    public struct LoadIssue: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            case invalidEvent
            case unsupportedSchemaVersion(Int)
        }

        public var id: Int { line }
        public let line: Int
        public let kind: Kind

        public var message: String {
            switch kind {
            case .invalidEvent:
                "Ignored invalid event on line \(line)."
            case .unsupportedSchemaVersion(let version):
                "Ignored schema version \(version) on line \(line)."
            }
        }
    }

    public struct Snapshot: Equatable, Sendable {
        public let events: [FactoryLogEvent]
        public let issues: [LoadIssue]
        public let dailyAggregates: [FactoryLogDailyAggregate]

        public init(
            events: [FactoryLogEvent],
            issues: [LoadIssue],
            dailyAggregates: [FactoryLogDailyAggregate] = []
        ) {
            self.events = events
            self.issues = issues
            self.dailyAggregates = dailyAggregates
        }
    }

    public struct StorageUsage: Equatable, Sendable {
        public let detailedBytes: Int64
        public let aggregateBytes: Int64
        public let detailedEventCount: Int
        public let aggregateCount: Int

        public var totalBytes: Int64 {
            detailedBytes + aggregateBytes
        }
    }

    public struct CompactionPreview: Equatable, Sendable {
        public let retentionDays: Int
        public let removableEventCount: Int
        public let protectedEventCount: Int
        public let cutoff: Date
    }

    public struct CompactionResult: Equatable, Sendable {
        public let retentionDays: Int
        public let removedEventCount: Int
        public let retainedEventCount: Int
        public let aggregateCount: Int
        public let bytesBefore: Int64
        public let bytesAfter: Int64

        public var bytesFreed: Int64 {
            max(bytesBefore - bytesAfter, 0)
        }
    }

    public let url: URL

    public var aggregateURL: URL {
        url.deletingLastPathComponent().appending(path: "daily-aggregates.json")
    }

    public init(url: URL = EventStoreLocation.defaultURL) {
        self.url = url
    }

    /// Appends a trusted event while serializing with every other Factory Log writer.
    /// Importers and tests can use this lower-level operation; user-facing mutations
    /// should use `appendValidated(_:)` so state validation shares the same lock.
    public func append(_ event: FactoryLogEvent) throws {
        try withLock(operation: LOCK_EX) {
            try appendUnlocked(event)
        }
    }

    /// Validates and appends one state transition as a single cross-process transaction.
    public func appendValidated(_ event: FactoryLogEvent) throws {
        try withLock(operation: LOCK_EX) {
            let snapshot = try loadSnapshotUnlocked()
            guard snapshot.issues.isEmpty else {
                throw StoreError.storeContainsIssues(lines: snapshot.issues.map(\.line))
            }

            let taskEvents = snapshot.events.filter { $0.taskID == event.taskID }
            switch event.kind {
            case .started:
                guard taskEvents.isEmpty else {
                    throw StoreError.taskAlreadyExists(event.taskID)
                }
            case .reported, .archived:
                guard let started = taskEvents.first(where: { $0.kind == .started }) else {
                    throw StoreError.taskNotStarted(event.taskID)
                }
                guard !taskEvents.contains(where: { $0.kind == .archived }) else {
                    throw StoreError.taskAlreadyArchived(event.taskID)
                }
                guard event.project == started.project, event.taskTitle == started.taskTitle else {
                    throw StoreError.taskMetadataMismatch(event.taskID)
                }
            }

            try appendUnlocked(event)
        }
    }

    /// Archives every open task whose start is at least `interval` seconds old.
    /// The scan and appends share one exclusive lock so concurrent reloads cannot
    /// create duplicate archive events.
    @discardableResult
    public func archiveStaleTasks(
        now: Date = Date()
    ) throws -> [FactoryLogEvent] {
        try withLock(operation: LOCK_EX) {
            let snapshot = try loadSnapshotUnlocked()
            guard snapshot.issues.isEmpty else {
                throw StoreError.storeContainsIssues(lines: snapshot.issues.map(\.line))
            }

            let cutoff = now.addingTimeInterval(-EventStore.automaticArchiveInterval)
            let staleTasks = FactoryLogHistory(events: snapshot.events)
                .doingTasks()
                .filter { $0.startedAt <= cutoff }
                .sorted { $0.startedAt < $1.startedAt }
            var archiveEvents: [FactoryLogEvent] = []

            for task in staleTasks {
                guard let latestEvent = task.events.last else {
                    continue
                }
                let archiveEvent = FactoryLogEvent(
                    taskID: task.taskID,
                    timestamp: now,
                    kind: .archived,
                    project: task.project,
                    taskTitle: task.title,
                    source: latestEvent.source,
                    summary: EventStore.automaticArchiveSummary
                )
                try appendUnlocked(archiveEvent)
                archiveEvents.append(archiveEvent)
            }

            return archiveEvents
        }
    }

    /// Loads all readable events and reports record-level compatibility problems
    /// without making the rest of an append-only history disappear.
    public func loadSnapshot() throws -> Snapshot {
        try withLock(operation: LOCK_SH) {
            try loadSnapshotUnlocked()
        }
    }

    public func loadEvents() throws -> [FactoryLogEvent] {
        try loadSnapshot().events
    }

    public func storageUsage() throws -> StorageUsage {
        try withLock(operation: LOCK_SH) {
            let snapshot = try loadSnapshotUnlocked()
            return StorageUsage(
                detailedBytes: fileSize(at: url),
                aggregateBytes: fileSize(at: aggregateURL),
                detailedEventCount: snapshot.events.count,
                aggregateCount: snapshot.dailyAggregates.count
            )
        }
    }

    public func compactionPreview(
        retainingDays retentionDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CompactionPreview {
        try validate(retentionDays: retentionDays)
        return try withLock(operation: LOCK_SH) {
            let snapshot = try loadSnapshotUnlocked()
            let plan = makeCompactionPlan(
                events: snapshot.events,
                retentionDays: retentionDays,
                now: now,
                calendar: calendar
            )
            return CompactionPreview(
                retentionDays: retentionDays,
                removableEventCount: plan.removed.count,
                protectedEventCount: plan.protectedOldEventCount,
                cutoff: plan.cutoff
            )
        }
    }

    public func compact(
        retainingDays retentionDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CompactionResult {
        try validate(retentionDays: retentionDays)
        return try withLock(operation: LOCK_EX) {
            let snapshot = try loadSnapshotUnlocked()
            guard snapshot.issues.isEmpty else {
                throw StoreError.storeContainsIssues(lines: snapshot.issues.map(\.line))
            }

            let plan = makeCompactionPlan(
                events: snapshot.events,
                retentionDays: retentionDays,
                now: now,
                calendar: calendar
            )
            let bytesBefore = fileSize(at: url) + fileSize(at: aggregateURL)

            guard !plan.removed.isEmpty else {
                return CompactionResult(
                    retentionDays: retentionDays,
                    removedEventCount: 0,
                    retainedEventCount: plan.retained.count,
                    aggregateCount: snapshot.dailyAggregates.count,
                    bytesBefore: bytesBefore,
                    bytesAfter: bytesBefore
                )
            }

            let aggregates = mergeAggregates(
                existing: snapshot.dailyAggregates,
                removedEvents: plan.removed,
                calendar: calendar
            )
            let fileManager = FileManager.default
            let previousAggregateData = try? Data(contentsOf: aggregateURL)
            let aggregatePreviouslyExisted = fileManager.fileExists(atPath: aggregateURL.path)
            try writeAggregatesUnlocked(aggregates)
            do {
                try writeEventsUnlocked(plan.retained)
            } catch {
                if let previousAggregateData {
                    try? previousAggregateData.write(to: aggregateURL, options: .atomic)
                } else if !aggregatePreviouslyExisted {
                    try? fileManager.removeItem(at: aggregateURL)
                }
                throw error
            }

            let bytesAfter = fileSize(at: url) + fileSize(at: aggregateURL)
            return CompactionResult(
                retentionDays: retentionDays,
                removedEventCount: plan.removed.count,
                retainedEventCount: plan.retained.count,
                aggregateCount: aggregates.count,
                bytesBefore: bytesBefore,
                bytesAfter: bytesAfter
            )
        }
    }

    private var lockURL: URL {
        url.appendingPathExtension("lock")
    }

    private struct AggregateDocument: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let aggregates: [FactoryLogDailyAggregate]

        init(aggregates: [FactoryLogDailyAggregate]) {
            self.schemaVersion = Self.currentSchemaVersion
            self.aggregates = aggregates
        }
    }

    private struct CompactionPlan {
        let cutoff: Date
        let retained: [FactoryLogEvent]
        let removed: [FactoryLogEvent]
        let protectedOldEventCount: Int
    }

    private struct AggregateKey: Hashable {
        let day: Date
        let projectPath: String
    }

    private struct MutableAggregate {
        var project: FactoryLogEvent.Project
        var updateCount: Int
        var taskIDs: Set<String>
    }

    private func withLock<T>(operation: Int32, _ body: () throws -> T) throws -> T {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        while flock(descriptor, operation) != 0 {
            guard errno == EINTR else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try body()
    }

    private func appendUnlocked(_ event: FactoryLogEvent) throws {
        var line = try FactoryLogJSON.makeEncoder().encode(event)
        line.append(0x0A)

        let descriptor = Darwin.open(url.path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        try line.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }

        guard fsync(descriptor) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func writeEventsUnlocked(_ events: [FactoryLogEvent]) throws {
        var data = Data()
        let encoder = FactoryLogJSON.makeEncoder()
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeAggregatesUnlocked(_ aggregates: [FactoryLogDailyAggregate]) throws {
        let document = AggregateDocument(aggregates: aggregates)
        let data = try FactoryLogJSON.makeEncoder().encode(document)
        try data.write(to: aggregateURL, options: .atomic)
    }

    private func loadSnapshotUnlocked() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Snapshot(events: [], issues: [], dailyAggregates: try loadAggregatesUnlocked())
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return Snapshot(events: [], issues: [], dailyAggregates: try loadAggregatesUnlocked())
        }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if data.last != 0x0A {
            lines.removeLast()
        }

        let decoder = FactoryLogJSON.makeDecoder()
        var events: [FactoryLogEvent] = []
        var issues: [LoadIssue] = []

        for (index, line) in lines.enumerated() where !line.isEmpty {
            let lineNumber = index + 1
            do {
                let event = try decoder.decode(FactoryLogEvent.self, from: Data(line))
                guard event.schemaVersion == FactoryLogEvent.currentSchemaVersion else {
                    issues.append(.init(
                        line: lineNumber,
                        kind: .unsupportedSchemaVersion(event.schemaVersion)
                    ))
                    continue
                }
                events.append(event)
            } catch {
                issues.append(.init(line: lineNumber, kind: .invalidEvent))
            }
        }

        return Snapshot(events: events, issues: issues, dailyAggregates: try loadAggregatesUnlocked())
    }

    private func loadAggregatesUnlocked() throws -> [FactoryLogDailyAggregate] {
        guard FileManager.default.fileExists(atPath: aggregateURL.path) else {
            return []
        }
        let data = try Data(contentsOf: aggregateURL)
        guard !data.isEmpty else {
            return []
        }
        let document = try FactoryLogJSON.makeDecoder().decode(AggregateDocument.self, from: data)
        guard document.schemaVersion == AggregateDocument.currentSchemaVersion else {
            return []
        }
        return document.aggregates
    }

    private func validate(retentionDays: Int) throws {
        guard retentionDays >= 30 else {
            throw StoreError.retentionTooShort(retentionDays)
        }
    }

    private func makeCompactionPlan(
        events: [FactoryLogEvent],
        retentionDays: Int,
        now: Date,
        calendar: Calendar
    ) -> CompactionPlan {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: today) ?? today
        let taskEvents = Dictionary(grouping: events, by: \.taskID)
        var protectedIDs: Set<String> = []

        for groupedEvents in taskEvents.values {
            let ordered = groupedEvents.sorted { $0.timestamp < $1.timestamp }
            guard ordered.last?.kind == .archived else {
                protectedIDs.formUnion(ordered.map(\.id))
                continue
            }
            if let started = ordered.first(where: { $0.kind == .started }) {
                protectedIDs.insert(started.id)
            }
            if let archived = ordered.last(where: { $0.kind == .archived }) {
                protectedIDs.insert(archived.id)
            }
        }

        var retained: [FactoryLogEvent] = []
        var removed: [FactoryLogEvent] = []
        var protectedOldEventCount = 0
        for event in events {
            if event.timestamp >= cutoff || protectedIDs.contains(event.id) {
                retained.append(event)
                if event.timestamp < cutoff, protectedIDs.contains(event.id) {
                    protectedOldEventCount += 1
                }
            } else {
                removed.append(event)
            }
        }

        return CompactionPlan(
            cutoff: cutoff,
            retained: retained,
            removed: removed,
            protectedOldEventCount: protectedOldEventCount
        )
    }

    private func mergeAggregates(
        existing: [FactoryLogDailyAggregate],
        removedEvents: [FactoryLogEvent],
        calendar: Calendar
    ) -> [FactoryLogDailyAggregate] {
        var values: [AggregateKey: MutableAggregate] = [:]

        for aggregate in existing {
            let key = AggregateKey(day: aggregate.day, projectPath: aggregate.project.path)
            values[key] = MutableAggregate(
                project: aggregate.project,
                updateCount: aggregate.updateCount,
                taskIDs: Set(aggregate.taskIDs)
            )
        }

        for event in removedEvents {
            let day = calendar.startOfDay(for: event.timestamp)
            let key = AggregateKey(day: day, projectPath: event.project.path)
            var aggregate = values[key] ?? MutableAggregate(
                project: event.project,
                updateCount: 0,
                taskIDs: []
            )
            aggregate.project = event.project
            aggregate.updateCount += 1
            aggregate.taskIDs.insert(event.taskID)
            values[key] = aggregate
        }

        return values.map { key, value in
            FactoryLogDailyAggregate(
                day: key.day,
                project: value.project,
                updateCount: value.updateCount,
                taskIDs: Array(value.taskIDs)
            )
        }
        .sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.project.path < $1.project.path
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}
