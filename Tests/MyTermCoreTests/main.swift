import Foundation
import Darwin
import MyTermCore

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--mcp-health-check" {
    let result = CodexMCPHealthCheck.run(executable: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("success=\(result.success) stage=\(result.stage.rawValue) reason=\(result.reason) code=\(String(describing: result.code))")
    exit(result.success ? 0 : 1)
}
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--codex-cluster-fixture" {
    let environment = ProcessInfo.processInfo.environment
    let client = try CodexThreadClient(executable: CommandLine.arguments[2], environment: environment)
    let id = try client.create(directory: CommandLine.arguments[3], name: "日常运维")
    checkEqual(try client.read(id, directory: CommandLine.arguments[3]), "日常运维")
    client.close()
    let reopened = try CodexThreadClient(executable: CommandLine.arguments[2], environment: environment)
    checkEqual(try reopened.read(id, directory: CommandLine.arguments[3]), "日常运维")
    checkThrows(try reopened.read(id, directory: "/different-cluster"))
    _ = try reopened.call("thread/name/set", params: ["threadId": id, "name": "GPU 与网络排查"])
    checkEqual(try reopened.read(id, directory: CommandLine.arguments[3]), "GPU 与网络排查")
    checkEqual(CodexConversationCheck.read(id: id, directory: CommandLine.arguments[3], client: reopened), .available(name: "GPU 与网络排查"))
    if case .unverified = CodexConversationCheck.read(id: id, directory: "/different-cluster", client: reopened) {} else {
        fatalError("A directory mismatch must remain unverified")
    }
    let missing = CodexConversationCheck.read(id: UUID().uuidString.lowercased(), directory: CommandLine.arguments[3], client: reopened)
    // CLI versions differ: "thread not loaded" is ambiguous and must not be called deleted.
    switch missing {
    case .missing, .unverified: break
    case .available: fatalError("An unknown UUID cannot be available")
    }
    reopened.close()
    print(id)
    exit(0)
}
if CommandLine.arguments.count == 7, CommandLine.arguments[1] == "--forward-fixture" {
    let rule = PortForward(kind: ForwardKind(rawValue: CommandLine.arguments[4])!,
                           listenPort: CommandLine.arguments[5], destinationPort: CommandLine.arguments[6])
    let result = SSHForwardControl.run(controlPath: CommandLine.arguments[2],
                                      operation: SSHForwardControl.Operation(rawValue: CommandLine.arguments[3])!, rule: rule)
    print(result.detail)
    exit(result.succeeded ? 0 : 1)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--codex-execution-fixture" {
    let arguments = try CodexExecutionPolicy.arguments(controlPath: CommandLine.arguments[2], host: "127.0.0.1", command: """
    printf 'mux-execution-fixture\\n'
    for item in one two; do
    \tprintf '%s\\n' "$item"
    done
    cat <<'MYTERM_END'
    $HOME 'quotes' 中文
    MYTERM_END
    printf 'stderr-fixture\\n' >&2
    exit 7
    """)
    let job = try CodexCommandProcess(arguments: arguments, timeout: 5)
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
        let result = try job.snapshot(offset: 0)
        if result["state"] as? String != "running" {
            print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)); exit(0)
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    job.cancel(); exit(1)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--codex-launch-arguments" {
    let args = try CodexConnection.launchArguments(appExecutable: CommandLine.arguments[2])
    print(String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
    exit(0)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--codex-socks-proxy", let port = UInt16(CommandLine.arguments[2]) {
    do {
        let relay = try CodexSOCKSProxy(host: "127.0.0.1", port: port, username: "fixture", password: "synthetic-proxy-password")
        var bytes = try JSONSerialization.data(withJSONObject: relay.environment(base: [:])); bytes.append(10)
        FileHandle.standardOutput.write(bytes)
        withExtendedLifetime(relay) { _ = readLine() }
        exit(0)
    } catch { fputs("Proxy fixture failed\n", stderr); exit(1) }
}
if CommandLine.arguments.dropFirst().first == "--password-integration", CommandLine.arguments.count == 5 {
    do { try realPasswordLogins(port: CommandLine.arguments[2], knownHosts: CommandLine.arguments[3], app: CommandLine.arguments[4]); exit(0) }
    catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
}

// Fixture-driven integration entrypoints use the same production argument builder and SFTP client.
if CommandLine.arguments.dropFirst().first == "--ssh-args", CommandLine.arguments.count == 6 {
    let input = try JSONDecoder().decode(Server.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    let server = try SSHConfigurationResolver.resolvingJump(input, configPath: CommandLine.arguments[3])
    let config = try server.proxyJumpConfig(userConfig: CommandLine.arguments[3])
    let configPath = config == nil ? CommandLine.arguments[3] : CommandLine.arguments[5]
    let result: [String: Any] = ["arguments": try server.sshArguments(controlPath: CommandLine.arguments[4], configPath: configPath), "config": config ?? "", "configPath": configPath, "server": String(decoding: try JSONEncoder().encode(server), as: UTF8.self)]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)); exit(0)
}
if CommandLine.arguments.dropFirst().first == "--sftp-ssh", CommandLine.arguments.count == 6 {
    let server = try JSONDecoder().decode(Server.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    let client = SFTPClient(arguments: try server.sftpArguments(controlPath: CommandLine.arguments[4], configPath: CommandLine.arguments[3]))
    defer { client.close() }
    try client.connect()
    let path = CommandLine.arguments[5]
    _ = try client.list(path)
    let source = URL(fileURLWithPath: path).appendingPathComponent("network-source")
    let target = path + "/network-upload-\(UUID().uuidString)"
    try client.upload(source, to: target) { _, _ in }
    let downloaded = URL(fileURLWithPath: target + ".download")
    try client.download(target, to: downloaded) { _, _ in }
    guard try Data(contentsOf: source) == Data(contentsOf: downloaded) else { exit(1) }

    print("PASS: SFTP over authenticated multiplexed SSH"); exit(0)
}

func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) -> Never {
    fputs("FAIL: \(message) (\(file):\(line))\n", stderr)
    exit(1)
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("\(actual) != \(expected)", file: file, line: line) }
}
func checkFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if actual { fail("Expected false", file: file, line: line) }
}
func checkGreaterThan<T: Comparable>(_ actual: T, _ minimum: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual <= minimum { fail("Expected \(actual) > \(minimum)", file: file, line: line) }
}
func checkThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    fail("Expected error: \(message)", file: file, line: line)
}
final class CheckExpectation {
    var fulfilled = false
    let description: String
    init(description: String = "") { self.description = description }
    func fulfill() { fulfilled = true }
}
func expectation(description: String) -> CheckExpectation { CheckExpectation(description: description) }
func wait(for expectations: [CheckExpectation], timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while !expectations.allSatisfy(\.fulfilled) && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    for item in expectations where !item.fulfilled { fail("Timed out: \(item.description)") }
}

let serverTests = ServerTests()
let ptyTests = PTYTests()
let features = FeatureTests()
let checks: [(String, () throws -> Void)] = [
    ("Tab appearance persistence and connection isolation", checkTabAppearance),
    ("Bilingual diagnostic summaries, unknown evidence, EOF and multiple helpers", checkDiagnosticSummary),
    ("MCP health probe launch failure, early exit and bounded timeout", checkMCPHealthFailures),
    ("MCP diagnostic lifecycle, bounds, expiry and symlink protection", checkMCPDiagnostics),
    ("Bounded opt-in terminal diagnostics, expiry, clearing and concurrent events", checkTerminalDiagnostics),
    ("Release versions, trusted assets and installer SHA-256 validation", checkAppRelease),
    ("Pane layouts, collapse, snapshot compatibility and shortcut conflicts", checkPaneLayouts),
    ("Opt-in history, line and byte limits, capacity eviction and cleanup", checkHistoryPolicy),
    ("Output highlight literal matching, boundaries, priority, limits and backup", checkOutputHighlight),
    ("trzsz literal paths, invalid drag input and saved connection options", checkTrzsz),
    ("Encrypted preferences backup, credential restore, tampering and resume throughput", checkBackupAndRates),
    ("Streaming character encodings, managed OpenSSH keys and OpenSSH export", checkNewFormats),
    ("Shared jump export deduplication, stable aliases and real OpenSSH resolution", checkSharedJumpExport),
    ("Shared jump migration, references, independent copies, credentials and corruption", checkSharedJumps),
    ("Standalone jump library, archive compatibility, deletion and probe routes", checkJumpLibrary),
    ("SSH inventory references, credential metadata and explicit key dependencies", checkConfigurationAudit),
    ("Session archive round trip, merge, repeat import and invalid/conflicting files", checkSessionArchive),
    ("Encrypted SQLite passwords: persistence, permissions, missing/wrong key and deletion", checkSQLitePasswords),
    ("Custom groups: move, rename, collapse, persistence and invalid edits", checkSessionGroups),
    ("Credential edits, legacy migration, rotation, endpoint isolation and key preservation", CredentialTests().configurationEdits),
    ("Password save, retry, rotation and challenge isolation", CredentialTests().passwordLifecycle),
    ("Authenticated askpass channel, cancellation and invalid token", CredentialTests().channelRoundTrip),
    ("SSH aliases preserve configured defaults", serverTests.testAliasKeepsSSHConfigDefaults),
    ("SSH arguments preserve literal key paths", serverTests.testArgumentsPreserveKeyPathAsSingleArgument),
    ("Host option / command injection rejected", serverTests.testRejectsHostOptionAndCommandInjection),
    ("Invalid ports rejected", serverTests.testRejectsInvalidPort),
    ("Configuration round trip and corruption", serverTests.testRepositoryRoundTripAndCorruption),
    ("Bash PTY input, Unicode, size and exit", ptyTests.testBashPTYInputOutputSizeAndExit),
    ("Interactive shell closes and is reaped", ptyTests.testCloseReapsInteractiveShell),
    ("Retained PTYs close after drain, EOF-before-exit and 100 cycles", ptyTests.testRetainedExitResources),
    ("Child ignoring HUP and TERM is closed and reaped", ptyTests.testUncooperativeChildCleanup),
    ("Compression, authentication, proxies, jumps and forwards", features.connectionOptions),
    ("SSH Include discovery and saved sessions", features.importAndSessions),
    ("Codex cluster catalog, stable identity and collision titles", checkCodexClusters),
    ("Codex read-only MCP, proxy isolation and snapshot cursors", checkCodexIntegration),
    ("Zmodem handshake detection across chunks", features.zmodemDetection),
    ("Recursive SFTP directories, resume, conflicts and symlinks", features.sftpDirectories),
    ("Real SFTP upload/download interruption and resume", features.sftpResume)
]
for (name, check) in checks {
    do { try check(); print("PASS: \(name)") }
    catch { fail("\(name): \(error)") }
}
print("All \(checks.count) checks passed.")
