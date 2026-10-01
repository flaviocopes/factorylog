import SwiftUI
import Synchronization
import FactoryLogCore

/// One color per project, the same in every view.
///
/// Hashing paths into a small palette makes busy projects collide, so the
/// projects with the most recent time take the palette in order and only the
/// long tail falls back to a hash. System colors stay distinct and adapt to
/// dark mode; their deeper shades extend the palette past twelve projects.
enum ProjectPalette {
    private static let baseColors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .mint, .cyan, .brown, .yellow]
    private static let colors = baseColors + baseColors.map { $0.mix(with: .black, by: 0.35) }
    private static let ranks = Mutex<[String: Int]>([:])

    /// `paths` ordered by time spent, most first.
    static func assign(ranking paths: [String]) {
        let ranking = Dictionary(paths.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        ranks.withLock { $0 = ranking }
    }

    /// Ranks projects by their last 30 days of sessions, then by all their time,
    /// so the projects on screen most often get the most distinct colors.
    static func assign(sessions: [FactoryLogWorkSession], excluding hidden: HiddenProjects, now: Date = Date()) {
        let recentStart = now.addingTimeInterval(-30 * 86_400)
        var recent: [String: TimeInterval] = [:]
        var total: [String: TimeInterval] = [:]
        for session in sessions where !hidden.contains(session.project.path) {
            total[session.project.path, default: 0] += session.duration
            if session.end >= recentStart {
                recent[session.project.path, default: 0] += session.duration
            }
        }
        assign(ranking: total.keys.sorted {
            let left = recent[$0] ?? 0
            let right = recent[$1] ?? 0
            if left != right {
                return left > right
            }
            return total[$0, default: 0] > total[$1, default: 0]
        })
    }

    static func color(for path: String) -> Color {
        if let rank = ranks.withLock({ $0[path] }), rank < colors.count {
            return colors[rank]
        }
        var hash: UInt64 = 5_381
        for scalar in path.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}
