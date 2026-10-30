import Foundation
import Darwin

/// Short-lived metadata client using the official app-server protocol. It never
/// starts a model turn. Run on a worker queue, and always close it after use.
public final class CodexThreadClient {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private let operationDeadline: TimeInterval?
    public init(executable: String, environment: [String: String], operationDeadline: TimeInterval? = nil) throws {
        self.operationDeadline = operationDeadline
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = CodexConnection.authenticationArguments + ["-c", #"mcp_servers.myterm={enabled=false,required=false,command="/usr/bin/false",args=[]}"#, "app-server", "--stdio"]
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        do {
            _ = try call("initialize", params: ["clientInfo": ["name": "myterm", "title": "MyTerm", "version": "1"]])
            try send(["method": "initialized", "params": [:]])
        } catch { close(); throw error }
    }
    deinit { close() }
    public func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? output.fileHandleForReading.close()
    }
    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    public func call(_ method: String, params: [String: Any]) throws -> [String: Any] {
        if let deadline = operationDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
            throw ConfigurationError.invalid("Codex 会话管理超时，请检查 CLI 和代理配置。")
        }
        nextID += 1; let id = nextID
        try send(["id": id, "method": method, "params": params])
        let deadline = min(ProcessInfo.processInfo.systemUptime + 30, operationDeadline ?? .infinity)
        while ProcessInfo.processInfo.systemUptime < deadline {
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                guard response["id"] as? Int == id else { continue }
                if let error = response["error"] as? [String: Any] {
                    throw CodexThreadRequestError(method: method, code: error["code"] as? Int,
                        message: error["message"] as? String ?? "Request failed")
                }
                guard let result = response["result"] as? [String: Any] else { throw ConfigurationError.invalid("Codex 返回了无效的会话信息。") }
                return result
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw ConfigurationError.invalid("无法读取 Codex 会话信息。") }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 16384)
                let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                guard count > 0 else { throw ConfigurationError.invalid("Codex 会话管理进程已退出，请检查 CLI 版本和配置。") }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 8 * 1048576 else { throw ConfigurationError.invalid("Codex 会话信息过大。") }
            }
        }
        throw ConfigurationError.invalid("Codex 会话管理超时，请检查 CLI 和代理配置。")
    }
    public func create(directory: String, name: String) throws -> String {
        let result = try call("thread/start", params: ["cwd": directory, "sandbox": "read-only", "approvalPolicy": "on-request"])
        guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String, UUID(uuidString: id) != nil else {
            throw ConfigurationError.invalid("Codex 返回了无效的会话信息。")
        }
        _ = try call("thread/name/set", params: ["threadId": id, "name": name])
        return id
    }
    public func read(_ id: String, directory: String) throws -> String? {
        let result = try call("thread/read", params: ["threadId": id, "includeTurns": false])
        guard let thread = result["thread"] as? [String: Any], thread["id"] as? String == id,
              let cwd = thread["cwd"] as? String,
              URL(fileURLWithPath: cwd).resolvingSymlinksInPath() == URL(fileURLWithPath: directory).resolvingSymlinksInPath() else {
            throw ConfigurationError.invalid("该 Codex 对话不属于所选集群目录。")
        }
        let name = thread["name"] as? String
        guard name == nil || (name!.count <= 1024 && !name!.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })) else {
            throw ConfigurationError.invalid("Codex 返回了无效的会话信息。")
        }
        return name
    }
}
