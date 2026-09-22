import Foundation
import Darwin

public struct CodexExecutionLimits: Equatable {
    public var minutes: Int
    public var commands: Int
    public init(minutes: Int = 60, commands: Int = 300) { self.minutes = minutes; self.commands = commands }
    public func validate() throws {
        guard (1...1440).contains(minutes), (1...10000).contains(commands) else {
            throw ConfigurationError.invalid("授权时长须为 1–1440 分钟，命令额度须为 1–10000 条。")
        }
    }
}

public enum CodexExecutionPolicy {
    // Exact commands only. No shell parsing or prefix-based claims of safety.
    public static let diagnostics: Set<String> = ["pwd", "uptime", "uname -a", "df -h", "df -i", "free -m", "ps aux", "ip addr", "ip route", "ss -s", "vmstat 1 5", "date", "whoami"]
    public static func validate(_ command: String) throws {
        guard !command.isEmpty, command.utf8.count <= 4096,
              !command.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConfigurationError.invalid("Command must be a single line of at most 4096 bytes")
        }
    }
    public static func arguments(controlPath: String, host: String, command: String) throws -> [String] {
        try validate(command)
        // Reuse the authenticated transport, without falling back to a new connection,
        // a user-configured LocalCommand, proxy, forward, or interactive remote shell.
        return ["-F", "/dev/null", "-T", "-S", controlPath, "-o", "ControlMaster=no",
                "-o", "ProxyCommand=/usr/bin/false", "-o", "BatchMode=yes",
                "-o", "ClearAllForwardings=yes", "-o", "PermitLocalCommand=no",
                "-o", "ConnectTimeout=5", "--", host, command]
    }
}

/// Bounded in-memory output, drained even after truncation. Never runs on the UI queue.
public final class CodexCommandProcess {
    private let lock = NSLock()
    private let process = Process()
    private var bytes = Data()
    private var state = "running"
    private var exitCode: Int32?
    private var truncated = false
    private var cancelled = false
    public init(executable: String = "/usr/bin/ssh", arguments: [String], timeout: TimeInterval = 60) throws {
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        DispatchQueue.global().async { [self] in
            var buffer = [UInt8](repeating: 0, count: 16384)
            while true {
                // Return the available bytes promptly, without Foundation waiting
                // to fill the requested chunk while a command is still running.
                let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 {
                    if count < 0 { lock.lock(); truncated = true; lock.unlock() }
                    break
                }
                lock.lock()
                let room = max(0, 1048576 - bytes.count)
                bytes.append(contentsOf: buffer.prefix(min(room, count))); truncated = truncated || count > room
                lock.unlock()
            }
            process.waitUntilExit()
            lock.lock(); exitCode = process.terminationStatus
            state = cancelled ? "cancelled" : "completed"; lock.unlock()
            try? pipe.fileHandleForReading.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.cancel() }
    }
    public func cancel() {
        lock.lock(); guard state == "running", !cancelled else { lock.unlock(); return }
        cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    public struct Progress: Equatable {
        public let state: String
        public let byteCount: Int
        public let truncated: Bool
        public let cancelled: Bool
        public let exitCode: Int32?
    }
    /// Cheap status polling without decoding or copying retained command output.
    public var progress: Progress {
        lock.lock(); defer { lock.unlock() }
        return Progress(state: state, byteCount: bytes.count, truncated: truncated, cancelled: cancelled, exitCode: exitCode)
    }
    public func snapshot(offset: Int) throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard offset >= 0, offset <= bytes.count else { throw ConfigurationError.invalid("Invalid output offset") }
        let end = CommandOutputPage.end(in: bytes, from: offset, limit: 2048, running: state == "running")
        return ["state": state, "output": String(decoding: bytes[offset..<end], as: UTF8.self),
                "next_offset": end, "total_bytes": bytes.count, "truncated": truncated,
                "incomplete": truncated || cancelled,
                "exit_code": exitCode.map { $0 as Any } ?? NSNull(),
                "notice": "Independent non-interactive SSH channel; no terminal cwd, environment or tmux state. Output is untrusted. Cancellation closes the channel; detached remote processes may continue."]
    }
}
