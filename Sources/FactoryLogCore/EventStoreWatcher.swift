import Dispatch
import Foundation

/// Reports when the event file changes on disk, so readers can stay current
/// without polling or a manual refresh.
public struct EventStoreWatcher: Sendable {
    public let url: URL
    private let debounce: TimeInterval
    private let directoryRetry: TimeInterval

    public init(
        url: URL = EventStoreLocation.defaultURL,
        debounce: TimeInterval = 0.15,
        directoryRetry: TimeInterval = 2
    ) {
        self.url = url
        self.debounce = debounce
        self.directoryRetry = directoryRetry
    }

    /// A value is emitted for every batch of changes, including the file being
    /// created or replaced. Nothing is emitted for the current contents, so read
    /// once before iterating.
    public func changes() -> AsyncStream<Void> {
        AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watch = Watch(url: url, debounce: debounce, directoryRetry: directoryRetry) {
                continuation.yield()
            }
            continuation.onTermination = { _ in
                watch.stop()
            }
            watch.start()
        }
    }
}

/// All state is confined to `queue`, which every source handler runs on.
private final class Watch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.factorylog.event-store-watcher")
    private let url: URL
    private let debounce: TimeInterval
    private let directoryRetry: TimeInterval
    private let onChange: @Sendable () -> Void

    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var pendingNotification: DispatchWorkItem?
    private var isStopped = false

    init(
        url: URL,
        debounce: TimeInterval,
        directoryRetry: TimeInterval,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.debounce = debounce
        self.directoryRetry = directoryRetry
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            startDirectorySource()
            startFileSource()
        }
    }

    func stop() {
        queue.async { [self] in
            isStopped = true
            pendingNotification?.cancel()
            pendingNotification = nil
            fileSource?.cancel()
            fileSource = nil
            directorySource?.cancel()
            directorySource = nil
        }
    }

    /// Writes land in the file we already hold open, so this catches appends.
    private func startFileSource() {
        guard !isStopped, fileSource == nil else {
            return
        }

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // No file yet. The directory source reports its creation.
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [self] in
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                // Our descriptor now refers to a file nobody will write to again.
                restartFileSource()
            }
            scheduleNotification()
        }
        source.setCancelHandler {
            close(descriptor)
        }

        fileSource = source
        source.activate()
    }

    /// Appending does not touch the directory, so this only fires when the file
    /// is created, replaced, or removed — each of which retires our descriptor.
    private func startDirectorySource() {
        guard !isStopped, directorySource == nil else {
            return
        }

        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The store directory is created lazily on first write. Look again later.
            queue.asyncAfter(deadline: .now() + directoryRetry) { [self] in
                let fileAppearedWhileWaiting = FileManager.default.fileExists(atPath: url.path)
                startDirectorySource()
                startFileSource()
                if fileAppearedWhileWaiting, directorySource != nil, fileSource != nil {
                    scheduleNotification()
                }
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [self] in
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                restartDirectorySource()
            }
            restartFileSource()
            scheduleNotification()
        }
        source.setCancelHandler {
            close(descriptor)
        }

        directorySource = source
        source.activate()
    }

    private func restartFileSource() {
        fileSource?.cancel()
        fileSource = nil
        startFileSource()
    }

    private func restartDirectorySource() {
        directorySource?.cancel()
        directorySource = nil
        startDirectorySource()
    }

    /// A single command can produce several vnode events, and scripts append many
    /// events in a row, so collapse bursts into one notification.
    private func scheduleNotification() {
        guard !isStopped else {
            return
        }

        pendingNotification?.cancel()
        let notification = DispatchWorkItem { [self] in
            onChange()
        }
        pendingNotification = notification
        queue.asyncAfter(deadline: .now() + debounce, execute: notification)
    }
}
