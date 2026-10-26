import Foundation
import Darwin

/// Tests the actual adapter, not registration metadata. Never calls a tool or reads a session.
public enum CodexMCPHealthCheck {
    public enum Stage: String, Codable { case launch, initialize, tools }
    public struct Result: Codable {
        public let success: Bool
        public let stage: Stage
        public let reason: String
        public let code: Int32?
        public init(success: Bool, stage: Stage, reason: String, code: Int32?) {
            self.success = success; self.stage = stage; self.reason = reason; self.code = code
        }
    }
    public static func run(executable: URL, arguments: [String] = ["--myterm-mcp"], timeout: TimeInterval = 8) -> Result {
        if FileManager.default.fileExists(atPath: executable.path), access(executable.path, X_OK) != 0 {
            return Result(success: false, stage: .launch, reason: "permission_denied", code: errno)
        }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        var stage = Stage.launch
        defer {
            try? input.fileHandleForWriting.close(); try? input.fileHandleForReading.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        do { try process.run() }
        catch {
            let failure = error as NSError
            let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError ?? failure
            let denied = (underlying.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying.code)) || (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
            return Result(success: false, stage: stage, reason: denied ? "permission_denied" : "launch_failed", code: Int32(underlying.code))
        }
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        let reader = output.fileHandleForReading.fileDescriptor, writer = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(reader, F_SETFL, O_NONBLOCK)
        _ = fcntl(writer, F_SETNOSIGPIPE, 1)
        let deadline = Date().addingTimeInterval(timeout)
        var buffered = Data(), total = 0
        func send(_ text: String) -> Bool {
            let data = Data(text.utf8)
            return data.withUnsafeBytes { Darwin.write(writer, $0.baseAddress, $0.count) } == data.count
        }
        for (id, method) in [(1, "initialize"), (2, "tools/list")] {
            stage = id == 1 ? .initialize : .tools
            if id == 2 && !send("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n") {
                return Result(success: false, stage: stage, reason: "write_failed", code: errno)
            }
            let params = id == 1 ? ",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"MyTermHealthCheck\",\"version\":\"1\"}}" : ""
            guard send("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"\(method)\"\(params)}\n") else {
                return Result(success: false, stage: stage, reason: "write_failed", code: errno)
            }
            var received = false
            while Date() < deadline {
                if let newline = buffered.firstIndex(of: 10) {
                    let line = Data(buffered.prefix(upTo: newline)); buffered.removeSubrange(...newline)
                    guard let reply = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                          reply["id"] as? Int == id, let result = reply["result"] as? [String: Any] else {
                        return Result(success: false, stage: stage, reason: "invalid_reply", code: nil)
                    }
                    let valid = id == 1 ? result["protocolVersion"] != nil : (result["tools"] as? [[String: Any]])?.contains { $0["name"] as? String == "list_sessions" } == true
                    guard valid else { return Result(success: false, stage: stage, reason: "invalid_reply", code: nil) }
                    received = true; break
                }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.read(reader, &bytes, bytes.count)
                let readError = errno
                if count > 0 {
                    total += count
                    guard total <= 65536 else { return Result(success: false, stage: stage, reason: "reply_limit", code: nil) }
                    buffered.append(contentsOf: bytes.prefix(count)); continue
                }
                if count == 0 || (!process.isRunning && count < 0) {
                    return Result(success: false, stage: stage, reason: "host_exited", code: process.isRunning ? nil : process.terminationStatus)
                }
                if readError != EAGAIN && readError != EINTR { return Result(success: false, stage: stage, reason: "read_failed", code: readError) }
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard received else { return Result(success: false, stage: stage, reason: "timeout", code: nil) }
        }
        // EOF allows the short-lived probe helper to exit normally.
        try? input.fileHandleForWriting.close()
        let exitDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.01) }
        return Result(success: true, stage: .tools, reason: "ok", code: nil)
    }
}
