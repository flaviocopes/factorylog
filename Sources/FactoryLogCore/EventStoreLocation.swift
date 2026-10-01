import Foundation

public enum EventStoreLocation {
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["FACTORYLOG_EVENTS_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
                .standardizedFileURL
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appending(
                path: "Library/Application Support/\(FactoryLogProduct.applicationSupportDirectoryName)",
                directoryHint: .isDirectory
            )
            .appending(path: "events.jsonl", directoryHint: .notDirectory)
    }
}
