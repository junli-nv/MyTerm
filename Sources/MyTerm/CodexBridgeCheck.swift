import AppKit
import SwiftUI
import MyTermCore

enum CodexBridgeCheck {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-codex-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Codex bridge: " + message) }
        }
        let workspace = Workspace(applicationSupportDirectory: root)
        let session = TerminalSession(label: "Synthetic SSH", executable: "/bin/bash", arguments: [], server: Server(host: "fixture.invalid"))
        let hidden = TerminalSession(label: "Hidden SSH", executable: "/bin/bash", arguments: [], server: Server(host: "hidden.invalid"))
        workspace.sessions = [session, hidden]; workspace.selectedID = session.id
        defer { workspace.stopAll() }
        let bridge = CodexBridge(workspace: workspace, descriptor: root.appendingPathComponent("bridge.json"), persist: false)
        defer { bridge.stop() }
        try require(!CodexChooserState().monitor && CodexChooserState().selected == nil, "Chooser defaults opt into monitoring or a session")
        bridge.start()
        try require(bridge.enabled, "Could not start isolated bridge")
        let other = CodexBridge(workspace: workspace, descriptor: root.appendingPathComponent("bridge.json"), persist: false)
        other.start()
        try require(!other.enabled && bridge.enabled, "Second app replaced the live bridge")
        try require((try bridge.read("list_sessions", arguments: [:])["sessions"] as? [[String: Any]])?.isEmpty == true, "Sharing enabled without per-tab consent")
        _ = try bridge.prepareSession(session.id)
        try require(bridge.monitored.isEmpty, "Default launch enabled monitoring")
        session.isRunning = true
        let idle = try bridge.read("watch_output", arguments: ["session_id": session.id.uuidString])
        try require(idle["stopped"] as? Bool == true, "Monitoring worked without opt-in")
        _ = try bridge.prepareSession(session.id, monitor: true)
        try require(bridge.monitored.contains(session.id), "Explicit monitor opt-in failed")
        session.terminal.feed(text: "first\r\nSSH fixture ready")
        let first = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString])
        try require((first["text"] as? String)?.contains("SSH fixture ready") == true, "Missing terminal history")
        session.terminal.feed(text: " plus more")
        let next = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString, "cursor": first["cursor"]!])
        try require(next["reset"] as? Bool == false && (next["text"] as? String)?.contains(" plus more") == true, "Incremental append failed")
        session.terminal.feed(text: "\u{1b}[?1049h\u{1b}[Hless current screen")
        let screen = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString, "view": "screen"])
        try require((screen["text"] as? String)?.contains("less current screen") == true, "Alternate screen missing")
        try require((try bridge.read("read_output", arguments: ["session_id": session.id.uuidString])["text"] as? String)?.contains("SSH fixture ready") == true, "Normal history lost in alternate screen")
        let watched = try bridge.read("watch_output", arguments: ["session_id": session.id.uuidString])
        try require(watched["view"] as? String == "screen" && (watched["text"] as? String)?.contains("less current screen") == true, "Monitor failed to follow alternate screen")
        bridge.stopMonitoring(session.id)
        try require((try bridge.read("watch_output", arguments: ["session_id": session.id.uuidString]))["stopped"] as? Bool == true, "Stop monitoring did not stop reads")
        _ = try bridge.prepareSession(session.id, monitor: true)
        session.isRunning = false
        try require((try bridge.read("watch_output", arguments: ["session_id": session.id.uuidString]))["stopped"] as? Bool == true, "Disconnect did not stop monitor")
        session.isRunning = true
        _ = try bridge.prepareSession(session.id, monitor: true)
        session.terminal.feed(text: "\u{1b}[?1049l")
        let viewport = session.terminal.getTerminal().buffer.yDisp
        session.terminal.feed(text: String(repeating: "中文 long line\r\n", count: 600))
        let limited = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString, "max_bytes": 256])
        try require((limited["text"] as? String)?.utf8.count ?? 99999 <= 256 && limited["truncated"] as? Bool == true, "Byte limit missing")
        let captured = try bridge.read("capture_history", arguments: ["session_id": session.id.uuidString])
        var pageCursor = captured["next_cursor"] as? String, allHistory = ""
        while let cursor = pageCursor {
            let page = try bridge.read("read_history_page", arguments: ["session_id": session.id.uuidString, "cursor": cursor])
            allHistory += page["text"] as? String ?? ""; pageCursor = page["next_cursor"] as? String
        }
        try require(allHistory.utf8.count > 8192 && allHistory.contains("SSH fixture ready"), "Paged history lost early diagnostic output")
        let before = session.terminal.getTerminal().buffer.yDisp
        _ = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString])
        try require(before == session.terminal.getTerminal().buffer.yDisp && viewport >= 0, "Read moved the viewport")
        for args: [String: Any] in [["session_id": hidden.id.uuidString], ["session_id": session.id.uuidString, "max_bytes": 0], ["session_id": session.id.uuidString, "max_lines": true]] {
            do { _ = try bridge.read("read_output", arguments: args); throw ConfigurationError.invalid("Expected rejection") }
            catch { try require(error.localizedDescription != "Expected rejection", "Invalid request accepted") }
        }
        // Exercise the real bundled stdio helper and authenticated socket without
        // loading real credentials, connecting SSH, or making a model request.
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--myterm-mcp", "--smoke-test"]
        var environment = ProcessInfo.processInfo.environment
        environment["MYTERM_TEST_CODEX_DESCRIPTOR"] = root.appendingPathComponent("bridge.json").path
        process.environment = environment; process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let requests: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "list_sessions", "arguments": [:]]],
            ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "read_output", "arguments": ["session_id": session.id.uuidString, "max_bytes": 256]]],
            ["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "watch_output", "arguments": ["session_id": session.id.uuidString, "max_bytes": 256]]]
        ]
        var initial = try JSONSerialization.data(withJSONObject: requests[0]); initial.append(10)
        try input.fileHandleForWriting.write(contentsOf: initial)
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 2000) > 0 else { process.terminate(); throw ConfigurationError.invalid("MCP waited for stdin EOF") }
        let firstResponse = output.fileHandleForReading.availableData
        for request in requests.dropFirst() {
            var bytes = try JSONSerialization.data(withJSONObject: request); bytes.append(10); try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        try input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard !process.isRunning else { process.terminate(); throw ConfigurationError.invalid("MCP helper timeout") }
        let responses = firstResponse + (try output.fileHandleForReading.readToEnd() ?? Data())
        let objects = try responses.split(separator: 10).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
        try require(process.terminationStatus == 0 && objects.count == 5, "MCP stdio exchange failed")
        let toolResult = objects[3]["result"] as? [String: Any]
        try require(toolResult?["isError"] as? Bool == false, "MCP tool failed")
        try require((objects[4]["result"] as? [String: Any])?["isError"] as? Bool == false, "MCP watch tool failed")
        try require(!String(decoding: responses, as: UTF8.self).contains("Hidden SSH"), "Private tab leaked")
        bridge.allowed.remove(session.id)
        try require(bridge.monitored.isEmpty, "Revocation retained monitor permission")
        do { _ = try bridge.read("read_output", arguments: ["session_id": session.id.uuidString]); throw ConfigurationError.invalid("Revocation failed") }
        catch { try require(error.localizedDescription != "Revocation failed", "Revoked tab readable") }
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { language.selection = original }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale; bridge.connection.proxyMode = .socks5
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let view = NSHostingView(rootView: CodexSettingsView(workspace: workspace, bridge: bridge))
            window.contentView = view; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); view.layoutSubtreeIfNeeded()
            guard let scroll = descendants(view).compactMap({ $0 as? NSScrollView }).first, let document = scroll.documentView else { throw ConfigurationError.invalid("Missing Codex settings scrollbar") }
            try require(document.frame.width <= scroll.contentSize.width + 1 && document.frame.height > scroll.contentSize.height, "Codex settings overflow horizontally or fail to scroll")
            let chooser = NSHostingView(rootView: CodexSessionChooser(workspace: workspace, bridge: bridge).environment(\.locale, language.locale))
            window.contentView = chooser
            window.setContentSize(NSSize(width: 558, height: 558))
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); chooser.layoutSubtreeIfNeeded()
            try require(descendants(chooser).contains(where: { $0 is NSScrollView }), "Session chooser missing scrollable list")
        }
        bridge.stop()
        try require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bridge.json").path) && bridge.allowed.isEmpty, "Disable did not revoke discovery")
        print("PASS: Codex MCP stdio + authenticated IPC, per-tab consent/revocation, history/alternate screen, incremental output, monitor opt-in/stop/disconnect, limits and bilingual settings/chooser")
    }
}
