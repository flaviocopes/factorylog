#if DEBUG
import AppKit
import SwiftUI

/// Lets a development script see the window without Screen Recording access:
/// the app draws its own window into a PNG on request.
///
/// Post the distributed notification `dev.factorylog.debug.snapshot` with an
/// object of the form `screen|/tmp/out.png`, where `screen` is an `AppScreen`
/// raw value, optionally followed by `@<project path>` to open that project's
/// panel, or empty to keep the current screen.
enum DebugSnapshot {
    static let notification = Notification.Name("dev.factorylog.debug.snapshot")

    /// Launched with `-DebugActiveWindow YES`, the app opens its main view in an
    /// `ActiveWindow` instead of the scene's window, so captures look frontmost.
    static let usesActiveWindow = UserDefaults.standard.bool(forKey: "DebugActiveWindow")

    struct Request {
        let screen: String
        let path: String

        init?(_ notification: Notification) {
            let parts = (notification.object as? String)?.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let parts, parts.count == 2 else {
                return nil
            }
            screen = String(parts[0])
            path = String(parts[1])
        }
    }

    /// A window launched from a script never becomes frontmost, so it would draw gray
    /// traffic lights and dimmed controls. AppKit decides that once, from these checks,
    /// so they have to answer from the moment the window exists.
    final class ActiveWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
        @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
        @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
        @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
    }

    @MainActor private static var activeWindow: ActiveWindow?

    @MainActor
    static func openActiveWindow<Content: View>(_ content: Content) {
        let controller = NSHostingController(rootView: content)
        controller.sceneBridgingOptions = [.toolbars]
        let window = ActiveWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 1_280, height: 860))
        window.center()
        window.makeKeyAndOrderFront(nil)
        activeWindow = window
    }

    @MainActor
    static func capture(to path: String) {
        guard let window = activeWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 300 }),
              let view = window.contentView?.superview ?? window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        try? representation.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }
}
#endif
