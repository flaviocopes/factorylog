import Foundation
import Testing

@Test
func cliReportsItsReleaseVersion() throws {
    let result = try runCLI(["--version"])

    #expect(result.status == 0)
    #expect(result.stdout == "factorylog 1.2.0\n")
    #expect(result.stderr.isEmpty)
}

@Test
func cliHelpListsCapabilitiesCommand() throws {
    let result = try runCLI(["--help"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("capabilities"))
    #expect(result.stderr.isEmpty)
}

@Test
func cliCapabilitiesManifestEncodesExpectedKeys() throws {
    let result = try runCLI(["capabilities", "--json"])

    #expect(result.status == 0)
    #expect(result.stderr.isEmpty)

    let manifest = try json(result.stdout)
    #expect(manifest["name"] as? String == "factorylog")
    #expect(manifest["version"] as? String == "1.2.0")
    #expect(manifest["summary"] as? String != nil)
    #expect((manifest["capabilities"] as? [[String: Any]])?.isEmpty == false)
    #expect((manifest["changelog"] as? [[String: Any]])?.isEmpty == false)
}

@Test
func cliPreservesItsMachineReadableSuccessAndFailureContract() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appending(path: "events.jsonl").path

    let started = try runCLI([
        "start", "--task-id", "task-contract", "--title", "Contract test",
        "--summary", "Started", "--project-path", directory.path,
        "--source", "codex", "--session-id", "codex-session", "--store", store
    ])
    #expect(started.status == 0)
    #expect(try json(started.stdout)["ok"] as? Bool == true)

    let reported = try runCLI([
        "report", "--task-id", "task-contract", "--summary", "Reported",
        "--source", "cursor", "--store", store
    ])
    #expect(reported.status == 0)
    let reportJSON = try json(reported.stdout)
    let event = reportJSON["event"] as? [String: Any]
    let source = event?["source"] as? [String: Any]
    #expect(source?["tool"] as? String == "cursor")
    #expect(source?["sessionID"] == nil)

    let duplicate = try runCLI([
        "start", "--task-id", "task-contract", "--title", "Duplicate",
        "--summary", "Duplicate", "--project-path", directory.path, "--store", store
    ])
    #expect(duplicate.status == 2)
    #expect(try json(duplicate.stderr)["ok"] as? Bool == false)
}

private struct CLIResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runCLI(_ arguments: [String]) throws -> CLIResult {
    let process = Process()
    process.executableURL = try cliURL()
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    return CLIResult(
        status: process.terminationStatus,
        stdout: String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        stderr: String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

private func cliURL() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let packageCandidate = packageRoot.appending(path: ".build/debug/factorylog")
    if FileManager.default.isExecutableFile(atPath: packageCandidate.path) {
        return packageCandidate
    }

    var directory = Bundle.main.bundleURL
    for _ in 0..<6 {
        let candidate = directory.appending(path: "factorylog")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        directory.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private func json(_ string: String) throws -> [String: Any] {
    try #require(
        JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any]
    )
}
