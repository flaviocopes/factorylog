// AppUpdater checks the app's GitHub repository for a newer release and installs it in place.
// Every app has an identical copy of this file. Change the template in the mac-app-updater
// skill, then copy it into each app.

import AppKit
import CryptoKit
import Security
import SwiftUI

@MainActor
final class AppUpdater {
  static let shared = AppUpdater()

  private static let checkInterval: TimeInterval = 24 * 60 * 60
  private static let lastCheckKey = "AppUpdaterLastCheck"
  private static let skippedVersionKey = "AppUpdaterSkippedVersion"
  private static let automaticChecksKey = "AppUpdaterAutomaticChecks"

  private var repository = ""
  private var isBusy = false
  private var timer: Timer?
  private let defaults = UserDefaults.standard

  /// Checks once a day, starting a few seconds after launch. `repository` is "owner/name" on GitHub.
  func start(repository: String) {
    self.repository = repository
    guard defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
      Task { @MainActor in AppUpdater.shared.checkIfDue() }
    }
    Task {
      try? await Task.sleep(for: .seconds(5))
      checkIfDue()
    }
  }

  /// For the "Check for Updates…" menu item.
  func checkForUpdates() {
    Task { await check(userInitiated: true) }
  }

  private var appName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? ProcessInfo.processInfo.processName
  }

  private var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  private func checkIfDue() {
    let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
    guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
    Task { await check(userInitiated: false) }
  }

  private func check(userInitiated: Bool) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let userAgent = "\(appName.replacingOccurrences(of: " ", with: ""))/\(currentVersion)"
      let release = try await Self.latestRelease(of: repository, userAgent: userAgent)
      defaults.set(Date(), forKey: Self.lastCheckKey)
      guard let release, Self.isVersion(release.version, newerThan: currentVersion) else {
        if userInitiated { showUpToDate() }
        return
      }
      if !userInitiated, defaults.string(forKey: Self.skippedVersionKey) == release.version { return }
      await offer(release)
    } catch {
      if userInitiated { showError(error, release: nil) }
    }
  }

  // MARK: - Dialogs

  private func offer(_ release: Release) async {
    let problem = installProblem(for: release)
    let alert = Self.offerAlert(appName: appName, currentVersion: currentVersion, release: release, problem: problem)
    NSApp.activate()

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      if problem == nil {
        await install(release)
      } else {
        NSWorkspace.shared.open(release.pageURL)
      }
    case .alertThirdButtonReturn:
      defaults.set(release.version, forKey: Self.skippedVersionKey)
    default:
      break
    }
  }

  static func offerAlert(appName: String, currentVersion: String, release: Release, problem: String?) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "\(appName) \(release.version) is available"
    alert.informativeText = ["You have \(currentVersion).", problem].compactMap { $0 }.joined(separator: " ")
    let notes = whatsNew(in: release.body ?? "")
    if !notes.isEmpty {
      let view = NSHostingView(rootView: ReleaseNotesView(markdown: notes))
      view.frame = NSRect(x: 0, y: 0, width: 380, height: 180)
      alert.accessoryView = view
    }
    alert.addButton(withTitle: problem == nil ? "Install and Relaunch" : "Open Release Page")
    alert.addButton(withTitle: "Later")
    alert.addButton(withTitle: "Skip This Version")
    return alert
  }

  private func installProblem(for release: Release) -> String? {
    let folder = Bundle.main.bundleURL.deletingLastPathComponent()
    if folder.path.contains("/AppTranslocation/") {
      return "To install updates, move \(appName) to your Applications folder and open it from there."
    }
    if !FileManager.default.isWritableFile(atPath: folder.path) {
      return "\(appName) can't replace itself in \(folder.path), so get the update from the release page."
    }
    if Self.asset(in: release.assets)?.digest == nil {
      return "This release has no download \(appName) can verify, so get it from the release page."
    }
    return nil
  }

  private func showUpToDate() {
    let alert = NSAlert()
    alert.messageText = "You're up to date"
    alert.informativeText = "\(appName) \(currentVersion) is the latest version."
    NSApp.activate()
    alert.runModal()
  }

  private func showError(_ error: Error, release: Release?) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = release.map { "Couldn't install \(appName) \($0.version)" } ?? "Couldn't check for updates"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    if release != nil { alert.addButton(withTitle: "Open Release Page") }
    NSApp.activate()
    if alert.runModal() == .alertSecondButtonReturn, let release {
      NSWorkspace.shared.open(release.pageURL)
    }
  }

  // MARK: - Installing

  private func install(_ release: Release) async {
    guard let asset = Self.asset(in: release.assets) else { return }
    let destination = Bundle.main.bundleURL
    let expected = Expected(bundleIdentifier: Bundle.main.bundleIdentifier ?? "", version: release.version)
    let progress = DownloadProgress()
    let download = Task {
      try await Self.prepare(asset, expected: expected, near: destination) { fraction in
        Task { @MainActor in progress.fraction = fraction }
      }
    }

    let window = Self.downloadWindow(appName: appName, version: release.version, progress: progress) {
      download.cancel()
    }
    window.center()
    window.makeKeyAndOrderFront(nil)

    do {
      let update = try await download.value
      window.close()
      try Self.replace(destination, with: update)
      relaunch()
    } catch {
      window.close()
      if !download.isCancelled { showError(error, release: release) }
    }
  }

  static func downloadWindow(
    appName: String, version: String, progress: DownloadProgress, cancel: @escaping () -> Void
  ) -> NSWindow {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: DownloadView(title: "Downloading \(appName) \(version)…", progress: progress, cancel: cancel)
      )
    )
    window.styleMask = [.titled]
    window.title = appName
    window.isReleasedWhenClosed = false
    return window
  }

  /// Waits for this process to exit, then opens the app again from the same place.
  func relaunch() {
    let shell = Process()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = [
      "-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; open \"$1\"",
      String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
    ]
    try? shell.run()
    NSApp.terminate(nil)
  }

  nonisolated static func latestRelease(of repository: String, userAgent: String) async throws -> Release? {
    guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
      throw UpdateError.response(0)
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
    case 200: return try JSONDecoder().decode(Release.self, from: data)
    case 404: return nil
    case let status: throw UpdateError.response(status)
    }
  }

  nonisolated static func isVersion(_ version: String, newerThan current: String) -> Bool {
    let numbers = { (text: String) in text.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 } }
    let new = numbers(version)
    let old = numbers(current)
    for index in 0..<max(new.count, old.count) {
      let a = index < new.count ? new[index] : 0
      let b = index < old.count ? old[index] : 0
      if a != b { return a > b }
    }
    return false
  }

  /// The zip for this Mac: a universal one, or the one named after this architecture.
  nonisolated static func asset(in assets: [Release.Asset]) -> Release.Asset? {
    #if arch(arm64)
      let otherArchitectures = ["x64", "x86_64", "intel"]
    #else
      let otherArchitectures = ["arm64"]
    #endif
    return assets.first { asset in
      let name = asset.name.lowercased()
      return name.hasSuffix(".zip") && !otherArchitectures.contains { name.contains($0) }
    }
  }

  /// The release notes up to the "## Install" heading, with headings and bullets made readable
  /// for inline Markdown.
  nonisolated static func whatsNew(in body: String) -> String {
    var lines: [String] = []
    for line in body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("## Install") { break }
      if line.hasPrefix("#") {
        lines.append("**\(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))**")
      } else if line.hasPrefix("- ") {
        lines.append("• \(line.dropFirst(2))")
      } else {
        lines.append(String(line))
      }
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Downloads the zip next to `destination`, then checks and unpacks it. Returns the new app.
  nonisolated static func prepare(
    _ asset: Release.Asset, expected: Expected, near destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    let folder = try FileManager.default.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
    do {
      let (downloaded, response) = try await URLSession.shared.download(
        from: asset.url, delegate: ProgressObserver(progress))
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200 else { throw UpdateError.download(status) }
      let zip = folder.appending(path: asset.name)
      try FileManager.default.moveItem(at: downloaded, to: zip)
      return try await Task.detached {
        try unpack(zip, digest: asset.digest, expected: expected, into: folder)
      }.value
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  nonisolated static func unpack(_ zip: URL, digest: String?, expected: Expected, into folder: URL) throws -> URL {
    guard let digest, digest == "sha256:\(try sha256(of: zip))" else { throw UpdateError.checksum }

    let ditto = Process()
    ditto.executableURL = URL(filePath: "/usr/bin/ditto")
    ditto.arguments = ["-x", "-k", zip.path, folder.path]
    try ditto.run()
    ditto.waitUntilExit()
    guard ditto.terminationStatus == 0 else { throw UpdateError.unzip }

    let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noApp }
    let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
    guard info?["CFBundleIdentifier"] as? String == expected.bundleIdentifier else { throw UpdateError.otherApp }
    let version = info?["CFBundleShortVersionString"] as? String ?? "none"
    guard version == expected.version else { throw UpdateError.version(version, expected: expected.version) }

    var code: SecStaticCode?
    let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate))
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
      SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    else { throw UpdateError.signature }
    return app
  }

  nonisolated static func sha256(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Swaps the new app into place without the old one's metadata, so it doesn't inherit a
  /// quarantine flag, then deletes the download folder.
  nonisolated static func replace(_ app: URL, with update: URL) throws {
    _ = try FileManager.default.replaceItemAt(
      app, withItemAt: update, backupItemName: nil, options: .usingNewMetadataOnly)
    try? FileManager.default.removeItem(at: update.deletingLastPathComponent())
  }

  // MARK: - Types

  nonisolated struct Release: Decodable, Sendable {
    let tag: String
    let body: String?
    let pageURL: URL
    let assets: [Asset]

    var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    enum CodingKeys: String, CodingKey {
      case tag = "tag_name", body, pageURL = "html_url", assets
    }

    nonisolated struct Asset: Decodable, Sendable {
      let name: String
      let url: URL
      /// "sha256:<hex>", computed by GitHub when the file was uploaded.
      let digest: String?

      enum CodingKeys: String, CodingKey {
        case name, url = "browser_download_url", digest
      }
    }
  }

  nonisolated struct Expected: Sendable {
    let bundleIdentifier: String
    let version: String
  }

  nonisolated enum UpdateError: LocalizedError {
    case response(Int), download(Int), checksum, unzip, noApp, otherApp, signature
    case version(String, expected: String)

    var errorDescription: String? {
      switch self {
      case .response(let status): "GitHub answered with status \(status). Try again later."
      case .download(let status): "The download failed with status \(status)."
      case .checksum: "The download doesn't match the checksum GitHub has for it."
      case .unzip: "The download couldn't be unzipped."
      case .noApp: "The download doesn't contain an app."
      case .otherApp: "The download contains a different app."
      case .version(let found, let expected): "The download contains version \(found), not \(expected)."
      case .signature: "The app in the download has an invalid code signature."
      }
    }
  }

  private nonisolated final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ report: @escaping @Sendable (Double) -> Void) {
      self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
      observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
        report(progress.fractionCompleted)
      }
    }
  }

  @MainActor @Observable
  final class DownloadProgress {
    var fraction = 0.0
  }

  private struct DownloadView: View {
    let title: String
    let progress: DownloadProgress
    let cancel: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        ProgressView(value: progress.fraction)
        HStack {
          Spacer()
          Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
      }
      .padding(20)
      .frame(width: 360)
    }
  }

  private struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
      ScrollView {
        Text(
          (try? AttributedString(
            markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        )
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
      }
      .frame(width: 380, height: 180)
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
  }
}
