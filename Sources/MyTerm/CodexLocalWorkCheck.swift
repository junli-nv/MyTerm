import AppKit
import SwiftUI
import MyTermCore

enum CodexLocalWorkCheck {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-local-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(applicationSupportDirectory: root)
        let bridge = CodexBridge(workspace: workspace, descriptor: root.appendingPathComponent("bridge.json"), persist: false)
        defer { bridge.stop(); workspace.stopAll() }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Local Codex: " + message) }
        }
        let fixture = root.appendingPathComponent("codex-fixture")
        try "#!/bin/bash\nprintf '%s\\n' \"$PWD\" \"$HTTPS_PROXY\" > \"$0.result\"\n".write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        bridge.connection.executable = fixture.path
        bridge.connection.proxyMode = .http; bridge.connection.host = "127.0.0.1"; bridge.connection.port = "18888"
        bridge.launch(checkSavedLogin: false, localDirectory: root.path)
        guard let tab = workspace.sessions.last else { throw ConfigurationError.invalid("Local launch missing") }
        try require(workspace.sessions.count == 1 && tab.directory == root.path && tab.codexTargetSessionID == nil && tab.codexExecutionBridge == nil, "Local launch lost directory/target")
        try require(tab.arguments.contains("workspace-write") && tab.arguments.contains("on-request"), "Local sandbox/approval missing")
        try require(bridge.executionGrants.isEmpty && bridge.allowed.isEmpty && !bridge.enabled, "Local tab acquired SSH permissions or shares Codex output")
        tab.start()
        // Read the child-written fixture, not main-queue PTY callbacks while
        // this synchronous UI check itself occupies the main queue.
        let resultURL = URL(fileURLWithPath: fixture.path + ".result")
        let deadline = Date().addingTimeInterval(3)
        var output = ""
        repeat {
            output = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? ""
            if output.contains(root.path) && output.contains("http://127.0.0.1:18888") { break }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline
        try require(output.contains(root.path) && output.contains("http://127.0.0.1:18888"), "Real local PTY lost working directory or proxy: \(String(reflecting: output))")
        let count = workspace.sessions.count
        bridge.launch(checkSavedLogin: false, localDirectory: root.appendingPathComponent("missing").path)
        try require(workspace.sessions.count == count && bridge.message == "请选择有效的本地工作目录。", "Invalid directory accepted")
        print("PASS: standalone local Codex without Bash/MCP, directory, sandbox, invalid-directory handling and real PTY proxy environment")
    }
}
