import Foundation

/// Multiplex control requests cannot fall back to a fresh authenticated connection.
/// They only change listeners on the existing transport; no remote shell is involved.
public enum SSHForwardControl {
    public enum Operation: String { case check, forward, cancel }
    public static func arguments(controlPath: String, operation: Operation, rule: PortForward? = nil) throws -> [String] {
        guard controlPath.hasPrefix("/"), !controlPath.contains("\0") else {
            throw ConfigurationError.invalid("Invalid SSH control path")
        }
        var args = ["-F", "/dev/null", "-S", controlPath, "-O", operation.rawValue,
                    "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "-o", "ExitOnForwardFailure=yes"]
        if operation != .check {
            guard let rule else { throw ConfigurationError.invalid("Missing forwarding rule") }
            args += try rule.arguments()
        }
        return args + ["--", "myterm-control"]
    }
    public struct Result {
        public let succeeded: Bool
        public let uncertain: Bool
        public let detail: String
        public init(succeeded: Bool, uncertain: Bool = false, detail: String = "") {
            self.succeeded = succeeded; self.uncertain = uncertain; self.detail = detail
        }
    }
    /// Call off the UI queue. Output and lifetime are bounded by the shared child-process runner.
    public static func run(controlPath: String, operation: Operation, rule: PortForward? = nil) -> Result {
        do {
            let job = try CodexCommandProcess(arguments: arguments(controlPath: controlPath, operation: operation, rule: rule),
                                               timeout: 4, maximumOutputBytes: 8192)
            let deadline = Date().addingTimeInterval(6)
            while job.progress.state == "running", Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if job.progress.state == "running" { job.cancel() }
            let snapshot = try job.snapshot(offset: 0)
            let uncertain = job.progress.state == "running" || snapshot["incomplete"] as? Bool == true
            return Result(succeeded: job.progress.exitCode == 0 && !uncertain, uncertain: uncertain,
                          detail: (snapshot["output"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return Result(succeeded: false, detail: error.localizedDescription) }
    }
}
