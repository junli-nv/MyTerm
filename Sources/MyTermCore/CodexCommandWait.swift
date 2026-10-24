import Foundation

/// Wait in the standalone MCP adapter, never on the GUI thread. Each socket
/// request remains short; the UI can approve, cancel or revoke while we wait.
public enum CodexCommandWait {
    public static func reply(tool: String,
                             now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                             sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                             fetch: () throws -> [String: Any]) throws -> [String: Any] {
        let deadline = now() + 20
        var value = try fetch()
        guard tool == "command_status" else { return value }
        let initialState = value["state"] as? String
        while ["running", "queued"].contains(value["state"] as? String ?? ""),
              value["state"] as? String == initialState,
              (value["output"] as? String ?? "").isEmpty,
              value["incomplete"] as? Bool != true,
              value["truncated"] as? Bool != true {
            let remaining = deadline - now()
            guard remaining > 0 else { break }
            sleep(min(1, remaining))
            value = try fetch()
        }
        return value
    }
}
