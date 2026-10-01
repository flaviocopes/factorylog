import Foundation

/// Day narratives written so far, stored beside the event log.
///
/// Narratives are expensive to produce and never change once their day stops
/// receiving updates, so they are written once and read back on every launch.
public struct NarrativeCache: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let signature: String
        public let model: String
        public let text: String
        public let writtenAt: Date
        /// Absent in caches written before wording rules were versioned, which
        /// reads as stale and earns those entries a rewrite.
        public let promptVersion: Int?

        public init(
            signature: String,
            model: String,
            text: String,
            writtenAt: Date = Date(),
            promptVersion: Int?
        ) {
            self.signature = signature
            self.model = model
            self.text = text
            self.writtenAt = writtenAt
            self.promptVersion = promptVersion
        }
    }

    public static var defaultURL: URL {
        EventStoreLocation.defaultURL
            .deletingLastPathComponent()
            .appending(path: "narratives.json", directoryHint: .notDirectory)
    }

    public let url: URL

    public init(url: URL = NarrativeCache.defaultURL) {
        self.url = url
    }

    public func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? FactoryLogJSON.makeDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    /// A failed write only costs a regenerated narrative, so it stays quiet.
    public func save(_ entries: [String: Entry]) {
        guard let data = try? FactoryLogJSON.makeEncoder().encode(entries) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
