import Foundation

/// Writes one plain sentence about a project's day using a local engine.
///
/// Everything here is best effort. A narrative is a nicety on top of the
/// factual rollup, so an unreachable engine returns nil instead of an error.
public actor DayNarrator {
    /// Long days are trimmed so the prompt stays small enough for a local model.
    private static let noteLimit = 40
    /// How long an unreachable engine is left alone before trying again.
    private static let retryDelay: TimeInterval = 60

    private let engine: NarrativeEngine
    private let model: String
    private let cache: NarrativeCache

    private var entries: [String: NarrativeCache.Entry]?
    private var pending: [String: Task<String?, Never>] = [:]
    private var unavailableSince: Date?

    public init(
        engine: NarrativeEngine = OllamaClient(),
        model: String = OllamaClient.Configuration.defaultModel,
        cache: NarrativeCache = NarrativeCache()
    ) {
        self.engine = engine
        self.model = model
        self.cache = cache
    }

    /// The stored narrative for this exact day of work, without generating one.
    public func cachedNarrative(for summary: FactoryLogProjectSummary, on day: Date) -> String? {
        let key = Self.key(for: summary, on: day)
        guard let entry = loadedEntries()[key],
              entry.signature == summary.signature,
              entry.promptVersion == Self.promptVersion,
              entry.model == model else {
            return nil
        }
        return entry.text
    }

    public func narrative(for summary: FactoryLogProjectSummary, on day: Date) async -> String? {
        if let cached = cachedNarrative(for: summary, on: day) {
            return cached
        }

        let key = Self.key(for: summary, on: day)
        let pendingKey = "\(key)|\(summary.signature)"
        if let existing = pending[pendingKey] {
            return await existing.value
        }

        // Inherits this actor's isolation, so the bookkeeping below stays serial
        // while the request itself is suspended.
        let task = Task<String?, Never> { [engine, model] in
            guard await self.engineIsReachable() else {
                return nil
            }

            let text: String
            do {
                text = try await engine.write(
                    system: Self.systemPrompt,
                    prompt: Self.prompt(for: summary, on: day)
                )
            } catch {
                self.markUnavailable()
                return nil
            }

            let sentence = Self.tidy(text)
            guard !sentence.isEmpty else {
                return nil
            }

            self.store(
                NarrativeCache.Entry(
                    signature: summary.signature,
                    model: model,
                    text: sentence,
                    promptVersion: Self.promptVersion
                ),
                forKey: key
            )
            return sentence
        }

        pending[pendingKey] = task
        let result = await task.value
        pending[pendingKey] = nil
        return result
    }

    private func engineIsReachable() async -> Bool {
        if let unavailableSince, Date().timeIntervalSince(unavailableSince) < Self.retryDelay {
            return false
        }

        guard await engine.isAvailable() else {
            unavailableSince = Date()
            return false
        }

        unavailableSince = nil
        return true
    }

    private func markUnavailable() {
        unavailableSince = Date()
    }

    private func loadedEntries() -> [String: NarrativeCache.Entry] {
        if let entries {
            return entries
        }
        let loaded = cache.load()
        entries = loaded
        return loaded
    }

    private func store(_ entry: NarrativeCache.Entry, forKey key: String) {
        var updated = loadedEntries()
        updated[key] = entry
        entries = updated
        cache.save(updated)
    }
}

public extension DayNarrator {
    /// Bumped whenever the wording rules change, so sentences written under the
    /// old rules are replaced instead of lingering in the cache.
    static let promptVersion = 2

    static let systemPrompt = """
    You describe a day of work on one software project, using notes that coding agents wrote as they worked.

    Rules:
    - Answer with one sentence. Two only if the day covered clearly separate things.
    - Start with a past-tense verb and name the work directly, like "Added a summary tab and cached its output."
    - Never name who did it. No "the team", "the project", "the developer", "we", or "I".
    - Use only what the notes say. Never invent work, causes, numbers, or outcomes.
    - Do not count the notes or mention tasks, updates, agents, or logs.
    - No markdown, lists, headings, quotes, or preamble. Reply with the sentence alone.
    """

    static func prompt(for summary: FactoryLogProjectSummary, on day: Date) -> String {
        let notes = summary.events.suffix(noteLimit).map { event in
            let time = event.timestamp.formatted(.dateTime.hour().minute())
            return "- \(time) \(event.taskTitle): \(event.summary)"
        }

        return """
        Project: \(summary.project.name)
        Day: \(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))

        Notes:
        \(notes.joined(separator: "\n"))
        """
    }

    static let doerPrefixes = [
        "the team ",
        "the project ",
        "the developer ",
        "the agent ",
        "this project ",
        "we ",
        "i "
    ]

    static func key(for summary: FactoryLogProjectSummary, on day: Date) -> String {
        "\(day.formatted(.iso8601.year().month().day()))|\(summary.project.path)"
    }

    /// Small models like to answer with a bulleted, quoted, or multi-line reply.
    static func tidy(_ text: String) -> String {
        var sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sentence = sentence
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        sentence = sentence.replacingOccurrences(of: "**", with: "")

        while let first = sentence.first, first == "-" || first == "*" || first == "•" {
            sentence = String(sentence.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        if sentence.count > 1, sentence.hasPrefix("\""), sentence.hasSuffix("\"") {
            sentence = String(sentence.dropFirst().dropLast())
        }

        // Small models narrate a doer even when told not to, and there is no
        // team here to speak of.
        for prefix in doerPrefixes where sentence.lowercased().hasPrefix(prefix) {
            sentence = String(sentence.dropFirst(prefix.count))
            sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
            break
        }

        return sentence.trimmingCharacters(in: .whitespaces)
    }
}
