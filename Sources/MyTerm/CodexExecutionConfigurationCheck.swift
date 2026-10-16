import Foundation
import MyTermCore

/// Bridge checks use a placeholder mux socket: ssh must fail closed, never connect anew.
enum CodexExecutionConfigurationCheck {
    static func run(bridge: CodexBridge, sessionID: UUID) throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid(message) }
        }
        let custom = CodexExecutionLimits(commandBytes: 32768, timeoutSeconds: 180, outputMiB: 2, alwaysAllow: true)
        try bridge.grantExecution(sessionID, limits: custom)
        let command = "# " + String(repeating: "x", count: 9000)
        let result = try bridge.read("execute_command", arguments: ["session_id": sessionID.uuidString, "command": command, "reason": "Configured limits fixture"])
        let metadata = result["execution_authorization"] as? [String: Any]
        try require(metadata?["command_limit_bytes"] as? Int == 32768 && metadata?["timeout_seconds"] as? Int == 180 && metadata?["output_limit_bytes"] as? Int == 2097152, "Configured limits missing from MCP")
        let record = bridge.executionRecords.last!
        try require(record.process != nil && record.command == command, "Configured Always allow or command length ignored")
        try require(try record.snapshot()["output_limit_bytes"] as? Int == 2097152, "Process used old output cap")
        let deadline = Date().addingTimeInterval(3)
        while record.process?.progress.state == "running" && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        record.process = try CodexCommandProcess(executable: "/usr/bin/perl", arguments: ["-e", "print 'x' x 1100000"], maximumOutputBytes: custom.outputBytes)
        while record.process?.progress.state == "running" && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        // Core checks cover every byte; emulate consumption to probe the bridge's old 1 MiB offset ceiling.
        record.deliveredOffset = 1099999
        let page = try bridge.read("command_status", arguments: ["session_id": sessionID.uuidString, "job_id": record.id.uuidString, "offset": 1099999])
        try require(page["all_output_delivered"] as? Bool == true && page["output"] as? String == "x", "Bridge rejected output beyond 1 MiB")
        bridge.setAlwaysAllowExecution(sessionID, enabled: false)
        bridge.renewExecution(sessionID)
        try require(!bridge.alwaysAllowedExecution.contains(sessionID) && bridge.limitsForExecution(sessionID).commandBytes == custom.commandBytes, "Renewal lost current configuration")
        bridge.renewExecution(sessionID, limits: CodexExecutionLimits(commandBytes: 1024))
        do {
            _ = try bridge.read("execute_command", arguments: ["session_id": sessionID.uuidString, "command": command, "reason": "Must reject oversized command"])
            throw ConfigurationError.invalid("Reduced command limit was ignored")
        } catch {
            try require(error.localizedDescription.contains("1024"), "Reduced command limit did not explain configured bound")
        }
        bridge.revokeExecution(sessionID)
        print("PASS: configured execution bounds, output beyond 1 MiB, approval default and renewal")
    }
}
