import AppKit
import MyTermCore

/// Uses real isolated Bash PTYs; files prove execution rather than merely echoed input.
enum PaneBroadcastCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-broadcast-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspace = Workspace(applicationSupportDirectory: directory.appendingPathComponent("settings"))
        let sessions = (0..<3).map { TerminalSession(label: "Broadcast \($0)", executable: "/bin/bash",
            arguments: ["--noprofile", "--norc"], directory: directory.path) }
        defer { sessions.forEach { $0.stop() }; try? FileManager.default.removeItem(at: directory) }
        workspace.sessions = sessions
        for session in sessions { session.start() }
        workspace.selectedID = sessions[0].id
        workspace.moveToSplit(sessions[1].id, beside: sessions[0].id, axis: .vertical)
        workspace.moveToSplit(sessions[2].id, beside: sessions[1].id, axis: .horizontal)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Broadcast: " + message) }
        }
        func select(_ targets: [TerminalSession]) {
            workspace.broadcastTargets = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.inputGeneration) })
        }
        func rejected(_ command: String, ready: Bool = true) throws {
            var failed = false
            do { try workspace.sendBroadcast(command, confirmedReady: ready) } catch { failed = true }
            try require(failed, "Unsafe/stale broadcast was accepted")
        }
        try require(sessions.allSatisfy(\.acceptsBroadcast), "Local PTYs did not start")
        workspace.beginBroadcast()
        try require(workspace.broadcastTargets.isEmpty, "Targets selected implicitly")
        try rejected("touch rejected")
        select(Array(sessions.prefix(2)))
        try rejected("touch rejected", ready: false)
        for invalid in ["", " \t", "touch rejected\ntrue", "touch rejected\r", "\u{1b}touch rejected", String(repeating: "x", count: 4097)] { try rejected(invalid) }
        let names = try workspace.sendBroadcast("printf broadcast-ok > received-$$", confirmedReady: true)
        try require(names == sessions.prefix(2).map(\.label), "Wrong target list")
        let files = sessions.map { directory.appendingPathComponent("received-\($0.terminal.process.shellPid)") }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !files.prefix(2).allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        try require(files.prefix(2).allSatisfy { (try? String(contentsOf: $0, encoding: .utf8)) == "broadcast-ok" }, "Commands did not execute in both PTYs")
        try require(!FileManager.default.fileExists(atPath: files[2].path), "Unselected pane received command")
        sessions[1].isCodexSession = true
        try rejected("touch rejected")
        sessions[1].isCodexSession = false
        workspace.broadcastTargets[sessions[1].id] = UUID()
        try rejected("touch rejected") // Reconnected process must be reselected.
        select(Array(sessions.prefix(2)))
        sessions[1].stop()
        try rejected("touch rejected")
        try require(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rejected").path), "A rejected batch partially executed")
        workspace.detachPane(sessions[2].id)
        try require(workspace.broadcastTabID == nil && workspace.broadcastTargets.isEmpty, "Layout change retained broadcast")
        workspace.selectedID = sessions[0].id
        workspace.beginBroadcast(); select([sessions[0]])
        workspace.selectedID = sessions[2].id
        try require(workspace.broadcastTabID == nil && workspace.broadcastTargets.isEmpty, "Switching tab retained broadcast")
        print("PASS: pane broadcast: real two-PTY execution, unselected isolation, explicit readiness, input bounds, Codex/disconnected/stale rejection, no partial batch and scope cleanup")
    }
}
