import AppKit
import MyTermCore

/// Exercise two real bridge clients against one transport. The SSH fixture uses
/// a missing mux socket; only bounded local processes simulate a busy channel.
enum CodexAssociationCheck {
    static func run(bridge: CodexBridge, session: TerminalSession, descriptorURL: URL) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Codex associations: " + message) }
        }
        let a = UUID(), b = UUID(), ownerA = UUID(), ownerB = UUID()
        defer {
            bridge.releaseExecution(session.id, tab: ownerA)
            bridge.releaseExecution(session.id, tab: ownerB)
        }
        try bridge.grantExecution(session.id, limits: .init(minutes: 60, commands: 2), association: a)
        bridge.ownExecution(a, tab: ownerA)
        let deadlineA = bridge.executionGrants[a]
        try bridge.grantExecution(session.id, limits: .init(minutes: 120, commands: 7), association: b)
        bridge.ownExecution(b, tab: ownerB)
        try require(bridge.executionGrants[a] == deadlineA && bridge.remainingExecutionCommands(a) == 2,
                    "Second association replaced first authorization")
        func call(_ name: String, _ client: UUID, _ extra: [String: Any] = [:]) throws -> [String: Any] {
            var arguments = extra; arguments["session_id"] = session.id.uuidString
            return try bridge.read(name, arguments: arguments, client: client.uuidString)
        }
        func submit(_ client: UUID) throws -> CodexExecutionRecord {
            _ = try call("execute_command", client, ["command": "pwd", "reason": "Association isolation fixture"])
            return bridge.executionRecords.last!
        }
        // Exercise the real stdio adapter: caller identity must come from its
        // environment, never from a model-controlled argument named client.
        let adapter = Process(), input = Pipe(), output = Pipe()
        adapter.executableURL = Bundle.main.executableURL
        adapter.arguments = ["--myterm-mcp", "--smoke-test"]
        var environment = ProcessInfo.processInfo.environment
        environment["MYTERM_TEST_CODEX_DESCRIPTOR"] = descriptorURL.path
        environment["MYTERM_CODEX_ASSOCIATION"] = a.uuidString
        adapter.environment = environment; adapter.standardInput = input
        adapter.standardOutput = output; adapter.standardError = FileHandle.nullDevice
        try adapter.run()
        defer { if adapter.isRunning { adapter.terminate() } }
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
            "name": "execute_command", "arguments": ["session_id": session.id.uuidString,
                "command": "pwd", "reason": "Scoped stdio regression", "client": b.uuidString]]]
        var bytes = try JSONSerialization.data(withJSONObject: request); bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes); try input.fileHandleForWriting.close()
        let ipcDeadline = Date().addingTimeInterval(5)
        while adapter.isRunning && Date() < ipcDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(!adapter.isRunning && adapter.terminationStatus == 0, "Scoped MCP adapter failed")
        let reply = try output.fileHandleForReading.readToEnd() ?? Data()
        try require(String(decoding: reply, as: UTF8.self).contains("awaiting_approval"), "Scoped IPC did not submit")
        let jobA = bridge.executionRecords.last!, jobB = try submit(b)
        try require(jobA.associationID == a, "Tool arguments changed adapter identity")
        try require(jobA.state == "awaiting_approval" && jobB.state == "awaiting_approval", "Pending approval crossed clients")
        try require(bridge.remainingExecutionCommands(a) == 1 && bridge.remainingExecutionCommands(b) == 6, "Quotas crossed clients")
        do {
            _ = try call("cancel_command", b, ["job_id": jobA.id.uuidString])
            throw ConfigurationError.invalid("Cross-client cancellation accepted")
        } catch { try require(error.localizedDescription.contains("Unknown execution job"), "Job ownership not enforced") }
        // Simulate an active SSH channel with deterministic bounded local output.
        jobA.state = "running"
        jobA.process = try CodexCommandProcess(executable: "/bin/bash", arguments: ["--noprofile", "--norc", "-c", "printf '%06000d' 0; sleep 0.4"])
        bridge.setAlwaysAllowExecution(b, enabled: true)
        try require(jobB.state == "queued" && jobB.process == nil && !bridge.alwaysAllowedExecution.contains(a), "Parallel channel or shared approval mode")
        let queued = try call("command_status", b, ["job_id": jobB.id.uuidString])
        try require(queued["all_output_delivered"] as? Bool == false, "Queued job incorrectly finished")
        let finish = Date().addingTimeInterval(4)
        while jobB.process?.progress.state != "completed" && Date() < finish {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03)); bridge.pollExecution()
        }
        try require(jobB.process?.progress.state == "completed", "Approved queue failed to advance")
        // B can finish and proceed while A still has unread output.
        _ = try call("command_status", b, ["job_id": jobB.id.uuidString])
        try require(jobA.deliveredOffset == 0, "B consumed A's output cursor")
        do { _ = try submit(a); throw ConfigurationError.invalid("Unread output accepted") }
        catch { try require(error.localizedDescription.contains("Read ALL"), "A output barrier lost") }
        var offset = 0, text = ""
        repeat {
            let page = try call("command_status", a, ["job_id": jobA.id.uuidString, "offset": offset])
            offset = page["next_offset"] as! Int; text += page["output"] as? String ?? ""
        } while offset < 6000
        try require(text.utf8.count == 6000, "A output incomplete")
        let remainingB = bridge.remainingExecutionCommands(b), deadlineB = bridge.executionGrants[b]
        bridge.reconcileExecution(now: Date().addingTimeInterval(61 * 60))
        try require(bridge.executionIsExpired(a) && bridge.executionGrants[a] == nil && bridge.executionGrants[b] == deadlineB,
                    "Expiry of A revoked the longer-lived B authorization")
        bridge.renewExecution(a, owner: ownerA)
        try require(bridge.remainingExecutionCommands(b) == remainingB && bridge.executionGrants[b] == deadlineB && bridge.alwaysAllowedExecution.contains(b), "Renewal affected sibling")
        bridge.releaseExecution(session.id, tab: ownerA)
        try require(bridge.executionGrants[b] == deadlineB, "Closing A revoked B")
        do { _ = try call("list_sessions", a); throw ConfigurationError.invalid("Closed client accepted") }
        catch { try require(error.localizedDescription.contains("association is closed"), "Closed client retained access") }
        let nextB = try submit(b)
        bridge.revokeExecution(b)
        try require(!bridge.alwaysAllowedExecution.contains(b), "Revocation retained mode")
        let stop = Date().addingTimeInterval(3)
        while nextB.process?.progress.state == "running" && Date() < stop {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        bridge.pollExecution()
        try require(!bridge.executionPollingActive, "Revoked clients retained idle timer")
        bridge.closedTab(session)
        try require(bridge.limitsForExecution(b) == CodexExecutionLimits() && bridge.executionGrants.isEmpty,
                    "Closing SSH after timer stopped retained authorization metadata")
        print("PASS: two Codex clients: independent authorization, quotas, approval, output pages; serialized commands, expiry, renewal and close cleanup")
    }
}
