import AppKit
import MyTermCore

enum CodexUploadBridgeCheck {
    static func run(bridge: CodexBridge, session: TerminalSession) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Codex transfer: " + message) }
        }
        let a = UUID(), b = UUID(), ownerA = UUID(), ownerB = UUID()
        defer { bridge.releaseExecution(session.id, tab: ownerA); bridge.releaseExecution(session.id, tab: ownerB) }
        try bridge.grantExecution(session.id, limits: .init(alwaysAllow: true), association: a)
        bridge.ownExecution(a, tab: ownerA)
        try bridge.grantExecution(session.id, association: b)
        bridge.ownExecution(b, tab: ownerB)
        let arguments: [String: Any] = ["session_id": session.id.uuidString, "local_paths": ["/tmp/fixture/kb", "/tmp/fixture/extra"],
            "remote_directory": "/data", "conflict": "skip", "exclude": [".git"], "reason": "Explicit upload fixture"]
        let result = try bridge.read("upload_items", arguments: arguments, client: a.uuidString)
        try require(result["state"] as? String == "awaiting_approval", "Command Always Allow silently approved local upload")
        let job = result["job_id"] as! String
        let record = bridge.executionRecords.first { $0.id.uuidString == job }!
        try require(record.transfer == nil && record.command.contains("/data") && record.command.contains(".git") && record.command.contains("skip"), "Approval summary lost upload policy")
        bridge.setAlwaysAllowExecution(a, enabled: true)
        try require(record.transfer == nil && record.state == "awaiting_approval", "Mode change silently approved an upload")
        let status: [String: Any] = ["session_id": session.id.uuidString, "job_id": job]
        do {
            _ = try bridge.read("transfer_status", arguments: status, client: b.uuidString)
            throw ConfigurationError.invalid("Sibling read another association's upload")
        } catch { try require(error.localizedDescription.contains("Unknown transfer"), "Unexpected isolation failure") }
        _ = try bridge.read("cancel_transfer", arguments: status, client: a.uuidString)
        let download = try bridge.read("download_items", arguments: ["session_id": session.id.uuidString,
            "remote_paths": ["/data/kb"], "local_directory": "/tmp", "reason": "Explicit download fixture"], client: a.uuidString)
        try require(download["state"] as? String == "awaiting_approval" && download["operation"] as? String == "download", "Download did not use separate approval")
        bridge.revokeExecution(a)
        try require(bridge.executionRecords.filter { $0.associationID == a }.allSatisfy { $0.state == "rejected" }, "Revocation retained pending transfer")
        bridge.revokeExecution(b)
        do {
            _ = try bridge.read("upload_items", arguments: arguments, client: b.uuidString)
            throw ConfigurationError.invalid("Read-only association uploaded")
        } catch { try require(error.localizedDescription.contains("active execution authorization"), "Unexpected read-only failure") }
        print("PASS: upload approval independent of command Always Allow, complete summary, sibling isolation and revocation/read-only boundaries")
    }
}
