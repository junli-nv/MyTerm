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
        let ended = TerminalSession(label: "Codex fixture", executable: "/bin/false", arguments: [], retainOnExit: true)
        var closed = false
        ended.onNormalExit = { closed = true }
        ended.terminal.feed(text: "synthetic startup error: required MCP servers failed to initialize: myterm: No such file or directory (os error 2)")
        ended.handleProcessTermination(exitCode: 256)
        try require(!closed && ended.status.contains("exit=1") && ended.statusBarVisible, "Codex failure closed its tab or hid exit status")
        try require(ended.historySnapshot().text.contains("synthetic startup error"), "Codex error output disappeared")
        try require(ended.status.contains("找不到 MyTerm MCP"), "Missing actionable MCP path diagnosis")
        ended.handleProcessTermination(exitCode: 0)
        try require(!closed && ended.status.contains("exit=0"), "Successful Codex exit closed tab")
        let loginCLI = root.appendingPathComponent("fake-codex")
        try "#!/bin/bash\nexit 0\n".write(to: loginCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: loginCLI.path)
        bridge.connection.executable = loginCLI.path
        let sessionCount = workspace.sessions.count
        bridge.launch(login: true)
        let loginDeadline = Date().addingTimeInterval(3)
        while bridge.busy && Date() < loginDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(!bridge.busy && workspace.sessions.count == sessionCount && bridge.message.hasPrefix("已保存 Codex"), "Saved login triggered another login tab")
        var ready = 0
        bridge.checkLogin(onReady: { ready += 1 })
        let readyDeadline = Date().addingTimeInterval(3)
        while bridge.busy && Date() < readyDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(ready == 1, "Saved login did not continue startup")
        try "#!/bin/bash\nexit 1\n".write(to: loginCLI, atomically: true, encoding: .utf8)
        var failureContinued = false
        bridge.checkLogin(onReady: { failureContinued = true })
        let failureDeadline = Date().addingTimeInterval(3)
        while bridge.busy && Date() < failureDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(!failureContinued, "Missing credentials started analysis")
        var completions = 0
        ended.onProcessExit = { if $0 == 0 { completions += 1 } }
        ended.handleProcessTermination(exitCode: 0)
        ended.handleProcessTermination(exitCode: 0)
        try require(completions == 1, "Login completion ran more than once")
        var stoppedCallback = 0
        ended.onProcessExit = { if $0 == nil { stoppedCallback += 1 } }
        ended.stop(); ended.stop()
        try require(stoppedCallback == 1, "Closing Codex failed to revoke exactly once")
        let registration = try JSONSerialization.data(withJSONObject: ["enabled": true, "transport": ["command": Bundle.main.executableURL!.path, "args": ["--myterm-mcp"]]])
        let fixture = root.appendingPathComponent("registration.json")
        try registration.write(to: fixture)
        try "#!/bin/bash\ncat \"$(dirname \"$0\")/registration.json\"\n".write(to: loginCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: loginCLI.path)
        bridge.refreshRegistration()
        let registrationDeadline = Date().addingTimeInterval(3)
        while bridge.checkingRegistration && Date() < registrationDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(bridge.registrationStatus == "外部 MCP 已注册，路径正确" && bridge.registrationPath == Bundle.main.executableURL!.path, "Registration status or path missing")
        let badRegistration = try JSONSerialization.data(withJSONObject: ["enabled": true, "transport": ["command": "/missing/MyTerm", "args": ["--myterm-mcp"]]])
        try badRegistration.write(to: fixture)
        bridge.refreshRegistration()
        let mismatchDeadline = Date().addingTimeInterval(3)
        while bridge.checkingRegistration && Date() < mismatchDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(bridge.registrationStatus.contains("不匹配"), "Missing stale registration warning")
        try registration.write(to: fixture)
        try "#!/bin/bash\nif [[ \"$2\" == add ]]; then echo 'fixture registration denied' >&2; exit 7; fi\ncat \"$(dirname \"$0\")/registration.json\"\n".write(to: loginCLI, atomically: true, encoding: .utf8)
        bridge.configureExternal()
        let configureDeadline = Date().addingTimeInterval(3)
        while (bridge.busy || bridge.checkingRegistration) && Date() < configureDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(bridge.registrationError.contains("exit=7") && bridge.registrationError.contains("fixture registration denied"), "Registration failure lost original error")
        try require(bridge.registrationStatus == "外部 MCP 已注册，路径正确", "Registration did not refresh after attempt")
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
            let chooserSelection = CodexChooserState()
            let chooser = NSHostingView(rootView: CodexSessionChooser(workspace: workspace, bridge: bridge, selection: chooserSelection).environment(\.locale, language.locale))
            window.contentView = chooser
            window.setContentSize(NSSize(width: 558, height: 558))
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); chooser.layoutSubtreeIfNeeded()
            chooserSelection.execute = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); chooser.layoutSubtreeIfNeeded()
            guard let chooserScroll = descendants(chooser).compactMap({ $0 as? NSScrollView }).first, let chooserDoc = chooserScroll.documentView else { throw ConfigurationError.invalid("Session chooser missing scrollable list") }
            try require(chooserDoc.frame.width <= chooserScroll.contentSize.width + 1 && chooserDoc.frame.height > chooserScroll.contentSize.height, "Expanded authorization limits do not fit/scroll")
        }
        let execServer = Server(host: "localhost")
        let execContext = try SSHLaunchContext(server: execServer)
        let execSession = TerminalSession(label: "Execution fixture", executable: "/usr/bin/ssh", arguments: [], server: execServer, context: execContext)
        workspace.sessions.append(execSession); execSession.isRunning = true
        bridge.allowed.insert(execSession.id)
        func deniedExecution() throws {
            do { _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd"]); throw ConfigurationError.invalid("execution unexpectedly allowed") }
            catch { try require(error.localizedDescription != "execution unexpectedly allowed", "Read-only execution gate failed") }
        }
        try deniedExecution()
        let readonlyPlan = try bridge.read("propose_plan", arguments: ["session_id": execSession.id.uuidString, "plan": "Read-only plan without execution authorization."])
        try require(readonlyPlan["state"] as? String == "presented" && bridge.executionGrants.isEmpty, "Plan display required or granted execution authorization")
        try deniedExecution()
        try require(!CodexChooserState().execute, "Unsafe execution/plan defaults")
        // A placeholder path permits authorization; real ssh must fail closed when it cannot multiplex.
        FileManager.default.createFile(atPath: execContext.controlPath, contents: Data())
        let windowsBeforeGrant = NSApp.windows.count
        try bridge.grantExecution(execSession.id)
        try require(NSApp.windows.count == windowsBeforeGrant, "Execution grant opened a popup")
        try deniedExecution() // A malformed command request must not execute.
        let plan = try bridge.read("propose_plan", arguments: ["session_id": execSession.id.uuidString, "plan": "Check fixture output; make no changes."])
        try deniedExecution()
        try require(plan["state"] as? String == "presented", "Plan incorrectly requested confirmation")
        let pending = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "printf fixture", "plan_id": plan["plan_id"]!, "reason": "Verify output capture"] )
        try require(pending["state"] as? String == "awaiting_approval", "Arbitrary shell command bypassed confirmation")
        let record = bridge.executionRecords.last!
        try require(NSApp.windows.count == windowsBeforeGrant, "Pending plan or command opened a popup")
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            let inlineWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            inlineWindow.isReleasedWhenClosed = false
            let inline = NSHostingView(rootView: CodexInlineExecutionView(bridge: bridge, sessionID: execSession.id))
            inlineWindow.contentView = inline; inlineWindow.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); inline.layoutSubtreeIfNeeded()
            try require(descendants(inline).contains(where: { $0 is NSScrollView }), "Inline approval missing scrollable command")
            try require(inline.fittingSize.width <= 541 && inline.fittingSize.height <= 180, "Inline controls wrapped or exceeded compact height")
            try require(record.state == "awaiting_approval" && record.process == nil, "Displaying inline approval executed command")
            inlineWindow.close()
        }
        bridge.cancelPlan(execSession.id)
        try require(bridge.executionRecords.first(where: { $0.id.uuidString == plan["plan_id"] as? String })?.state == "cancelled", "Plan cancellation was not recorded")
        try require(bridge.executionGrants[execSession.id] == nil, "Cancelled plan retained execution permission")
        bridge.approveExecution(record)
        try require(record.process == nil && record.state == "rejected", "Stale approval executed after revocation")
        try bridge.grantExecution(execSession.id)
        _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd", "reason": "Check directory"])
        let automatic = bridge.executionRecords.last!
        try require(automatic.process == nil && automatic.state == "awaiting_approval", "Diagnostic command bypassed explicit confirmation")
        bridge.approveExecution(automatic)
        let execDeadline = Date().addingTimeInterval(5)
        while (try automatic.snapshot()["state"] as? String) == "running" && Date() < execDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require((try automatic.snapshot()["exit_code"] as? Int32) == 255, "Missing mux connection did not fail closed")
        automatic.process = try CodexCommandProcess(executable: "/bin/bash", arguments: ["--noprofile", "--norc", "-c", "printf '%06000d' 0; printf END >&2"])
        automatic.deliveredOffset = 0
        let pageDeadline = Date().addingTimeInterval(3)
        while (try automatic.snapshot()["state"] as? String) == "running" && Date() < pageDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        do { _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd", "reason": "Next step"]); throw ConfigurationError.invalid("Unread output bypass") }
        catch { try require(error.localizedDescription.contains("Read ALL"), "Next command did not require complete output") }
        do { _ = try bridge.read("command_status", arguments: ["session_id": execSession.id.uuidString, "job_id": automatic.id.uuidString, "offset": 4096]); throw ConfigurationError.invalid("Skipped output") }
        catch { try require(error.localizedDescription.contains("Cannot skip"), "Output cursor allowed skipping pages") }
        var offset = 0, fullOutput = "", allDelivered = false
        repeat {
            let page = try bridge.read("command_status", arguments: ["session_id": execSession.id.uuidString, "job_id": automatic.id.uuidString, "offset": offset])
            fullOutput += page["output"] as? String ?? ""
            offset = page["next_offset"] as! Int; allDelivered = page["all_output_delivered"] as? Bool == true
        } while !allDelivered && offset < 7000
        try require(fullOutput.utf8.count == 6003 && fullOutput.hasSuffix("END"), "Paginated command output lost content")
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            let checkWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            checkWindow.isReleasedWhenClosed = false
            let executionView = NSHostingView(rootView: CodexExecutionView(bridge: bridge))
            checkWindow.contentView = executionView; checkWindow.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); executionView.layoutSubtreeIfNeeded()
            guard let scroll = descendants(executionView).compactMap({ $0 as? NSScrollView }).first, let document = scroll.documentView else { throw ConfigurationError.invalid("Execution view missing scrollbar") }
            try require(document.frame.width <= scroll.contentSize.width + 1 && document.frame.height > scroll.contentSize.height, "Execution view overflow or missing vertical scroll")
            checkWindow.close()
        }
        automatic.process = try CodexCommandProcess(executable: "/usr/bin/yes", arguments: ["bounded-output"], timeout: 0.1)
        automatic.deliveredOffset = 0
        let truncateDeadline = Date().addingTimeInterval(3)
        while (try automatic.snapshot()["state"] as? String) == "running" && Date() < truncateDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        do { _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd", "reason": "Next step"]); throw ConfigurationError.invalid("Incomplete output bypass") }
        catch { try require(error.localizedDescription.contains("incomplete"), "Incomplete output did not stop automatic progression") }
        execSession.isRunning = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        try require(bridge.executionGrants.isEmpty, "Disconnect retained execution authorization")
        try deniedExecution()
        let disconnectedPlan = try bridge.read("propose_plan", arguments: ["session_id": execSession.id.uuidString, "plan": "Explain diagnostics while the SSH execution channel is disconnected."])
        try require(disconnectedPlan["state"] as? String == "presented", "Disconnected execution blocked plan display")
        execSession.isRunning = true
        try bridge.grantExecution(execSession.id, limits: CodexExecutionLimits(minutes: 120, commands: 1))
        try require((bridge.executionGrants[execSession.id]?.timeIntervalSinceNow ?? 0) > 7190, "Custom duration ignored")
        _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd", "reason": "Budget fixture"])
        bridge.cancelExecution(bridge.executionRecords.last!)
        try require(bridge.remainingExecutionCommands(execSession.id) == 0, "Custom command budget ignored")
        do { _ = try bridge.read("execute_command", arguments: ["session_id": execSession.id.uuidString, "command": "pwd", "reason": "Budget exceeded"]); throw ConfigurationError.invalid("Budget bypass") }
        catch { try require(error.localizedDescription.contains("budget exhausted"), "Budget exhaustion did not explain renewal") }
        bridge.revokeExecution(execSession.id)
        let tabA = UUID(), tabB = UUID()
        bridge.renewExecution(execSession.id, owner: tabA)
        try require(bridge.executionGrants[execSession.id] != nil, "Existing tab could not renew execution access")
        try require(bridge.remainingExecutionCommands(execSession.id) == 1 && bridge.limitsForExecution(execSession.id).minutes == 120, "Renewal did not retain custom limits or reset budget")
        bridge.renewExecution(execSession.id, owner: tabB)
        bridge.releaseExecution(execSession.id, tab: tabA)
        try require(bridge.executionGrants[execSession.id] != nil, "Old Codex tab revoked a newer tab's access")
        bridge.releaseExecution(execSession.id, tab: tabB)
        try require(bridge.executionGrants[execSession.id] == nil, "Owning tab did not revoke execution on close")
        try deniedExecution()
        bridge.pollExecution()
        try require(!bridge.executionPollingActive, "Idle execution timer retained after revocation")
        var idleRefreshes = 0
        let idleSubscription = bridge.objectWillChange.sink { idleRefreshes += 1 }
        let idleStart = Date()
        for _ in 0..<1000 { bridge.pollExecution() }
        try require(idleRefreshes == 0, "Unchanged execution history continuously invalidated UI")
        print("PASS: 1000 unchanged execution polls: \(Date().timeIntervalSince(idleStart))s, zero UI invalidations")
        idleSubscription.cancel()
        bridge.renewExecution(execSession.id, owner: tabB)
        try require(bridge.executionPollingActive, "Renewal did not restart expiry checks")
        bridge.pollExecution()
        var activeRefreshes = 0
        let activeSubscription = bridge.objectWillChange.sink { activeRefreshes += 1 }
        for _ in 0..<1000 { bridge.pollExecution() }
        try require(activeRefreshes == 0, "Unchanged authorization continuously invalidated UI")
        activeSubscription.cancel()
        bridge.revokeExecution(execSession.id)

        print("PASS: Codex execution default-off, exact-command approval, revocation, stale approval, mux-only failure and disconnect")
        let launchWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        launchWindow.isReleasedWhenClosed = false
        var didCloseAfterLaunch = false
        launchWindow.contentView = NSHostingView(rootView: CodexSettingsView(workspace: workspace, bridge: bridge, onStarted: { didCloseAfterLaunch = true; launchWindow.close() }))
        launchWindow.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        bridge.connection.proxyMode = .inherited
        let generation = bridge.launchGeneration
        bridge.launch(sessionID: session.id, checkSavedLogin: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try require(bridge.launchGeneration == generation + 1 && didCloseAfterLaunch && !launchWindow.isVisible, "Successful launch did not dismiss integration window")
        try require(workspace.selected?.codexTargetSessionID == session.id, "Codex launch lost selected SSH target")
        bridge.stop()
        try require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bridge.json").path) && bridge.allowed.isEmpty, "Disable did not revoke discovery")
        let beforeLoginTabs = workspace.sessions.count
        bridge.connection.proxyMode = .inherited
        bridge.launch(login: true, checkSavedLogin: false)
        try require(workspace.sessions.count == beforeLoginTabs + 1 && !bridge.enabled && bridge.allowed.isEmpty, "Login requires or enables SSH access")
        workspace.selected?.stop()
        print("PASS: Codex MCP stdio + authenticated IPC, per-tab consent/revocation, history/alternate screen, incremental output, monitor opt-in/stop/disconnect, limits and bilingual settings/chooser")
    }
}


extension CodexBridgeCheck {
    // Run in a separate app process with a free main queue: SwiftTerm delivers
    // PTY data/exit events on that queue, so a nested synchronous check cannot
    // exercise this lifecycle faithfully.
    static func runLoginLifecycle() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-login-\(UUID())")
        let workspace = Workspace(applicationSupportDirectory: root)
        let bridge = CodexBridge(workspace: workspace, descriptor: root.appendingPathComponent("bridge.json"), persist: false)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let executable = root.appendingPathComponent("fake-codex")
            try """
            #!/bin/bash
            marker="$(dirname "$0")/signed-in"
            case "$*" in
              *"login status"*) test -f "$marker"; exit $? ;;
              *"login --device-auth"*) touch "$marker"; echo "Synthetic login completed"; exit 0 ;;
              *) echo "Synthetic analysis started"; exit 0 ;;
            esac
            """.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            bridge.connection.executable = executable.path
            let ssh = TerminalSession(label: "Synthetic SSH", executable: "/bin/bash", arguments: [], server: Server(host: "fixture.invalid"))
            workspace.sessions = [ssh]
            bridge.start()
            bridge.launch(sessionID: ssh.id)
            var phase = 0
            let deadline = Date().addingTimeInterval(8)
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                func finish(_ error: String? = nil) {
                    timer.invalidate(); bridge.stop(); workspace.stopAll()
                    try? FileManager.default.removeItem(at: root)
                    if let error { fputs("FAIL: Codex login lifecycle: \(error)\n", stderr); exit(1) }
                    print("PASS: Codex real PTY login-to-analysis continuation, selected SSH target, default monitoring off and retained exit results")
                    NSApp.terminate(nil)
                }
                if Date() > deadline { finish("Timed out at phase \(phase)"); return }
                switch phase {
                case 0 where workspace.sessions.count == 2:
                    guard workspace.sessions[1].arguments.contains("--device-auth") else { finish("Skipped required login"); return }
                    phase = 1; workspace.sessions[1].start()
                case 1 where workspace.sessions.count == 3:
                    guard workspace.sessions[2].arguments.last?.contains(ssh.id.uuidString) == true,
                          !bridge.monitored.contains(ssh.id) else { finish("Lost target or enabled monitoring"); return }
                    phase = 2; workspace.sessions[2].start()
                case 2 where workspace.sessions[2].status.contains("exit=0"):
                    guard workspace.sessions[1].status.contains("exit=0"), workspace.sessions.count == 3 else { finish("Did not retain login result"); return }
                    finish()
                default: break
                }
            }
        } catch {
            bridge.stop(); workspace.stopAll(); try? FileManager.default.removeItem(at: root)
            fputs("FAIL: Codex login lifecycle setup\n", stderr); exit(1)
        }
    }
}
