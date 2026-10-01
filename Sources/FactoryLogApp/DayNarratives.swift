import SwiftUI
import FactoryLogCore

/// Holds the one-line recaps a local model writes for each project's day.
///
/// Rows ask for their narrative as they appear and keep showing the factual
/// rollup meanwhile, so a slow or absent model never holds up the view.
@MainActor
@Observable
final class DayNarratives {
    enum State: Equatable {
        case missing
        case writing
        case written(String)
    }

    private let narrator: DayNarrator
    private let retryDelay: Duration
    private var states: [String: State] = [:]

    init(narrator: DayNarrator = DayNarrator(), retryDelay: Duration = .seconds(60)) {
        self.narrator = narrator
        self.retryDelay = retryDelay
    }

    func state(for summary: FactoryLogProjectSummary, on day: Date) -> State {
        states[Self.key(for: summary, on: day)] ?? .missing
    }

    func load(_ summary: FactoryLogProjectSummary, on day: Date) async {
        let key = Self.key(for: summary, on: day)
        guard states[key] == nil || states[key] == .missing else {
            return
        }

        if let cached = await narrator.cachedNarrative(for: summary, on: day) {
            states[key] = .written(cached)
            return
        }

        while !Task.isCancelled {
            states[key] = .writing
            let text = await narrator.narrative(for: summary, on: day)

            guard !Task.isCancelled else {
                states[key] = nil
                return
            }
            if let text {
                states[key] = .written(text)
                return
            }

            states[key] = .missing
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                states[key] = nil
                return
            }
        }

        states[key] = nil
    }

    private static func key(for summary: FactoryLogProjectSummary, on day: Date) -> String {
        "\(DayNarrator.key(for: summary, on: day))|\(summary.signature)"
    }
}
