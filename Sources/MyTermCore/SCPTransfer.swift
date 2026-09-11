import Foundation

/// System scp writes only the resume engine's staging file. SFTP finalizes or resumes it.
public final class SCPTransfer {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private let server: Server
    private let controlPath: String
    private let configPath: String?
    public init(server: Server, controlPath: String, configPath: String?) {
        self.server = server; self.controlPath = controlPath; self.configPath = configPath
    }
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
    public func transfer(local: URL, remote: String, upload: Bool, progress: (() -> Void)? = nil) throws {
        let server = try server.validated()
        guard remote.hasPrefix("/"), !remote.contains("\n"), !remote.contains("\0") else { throw ConfigurationError.invalid("SCP 需要有效的绝对远端路径。") }
        var args = ["-B", "-o", "ControlPath=\(controlPath)", "-o", "ControlMaster=no", "-o", "ProxyCommand=false", "-o", "ConnectTimeout=10", "-o", "ClearAllForwardings=yes"]
        let options = try server.connectionArguments(configPath: configPath)
        var index = 0
        while index < options.count {
            let flag = options[index], value = options[index + 1]; index += 2
            // The authenticated control socket already owns proxy/jump routing.
            if flag == "-J" || (flag == "-o" && value.hasPrefix("ProxyCommand=")) { continue }
            if flag == "-p" { args += ["-P", value] }
            else if flag == "-l" { args += ["-o", "User=\(value)"] }
            else { args += [flag, value] }
        }
        let host = server.host.contains(":") && !server.host.hasPrefix("[") ? "[\(server.host)]" : server.host
        let target = "\(host):\(remote)"
        args += ["--"] + (upload ? [local.path, target] : [target, local.path])
        let child = Process(), errors = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/scp"); child.arguments = args
        child.standardInput = FileHandle.nullDevice; child.standardOutput = FileHandle.nullDevice; child.standardError = errors
        lock.lock()
        if cancelled { lock.unlock(); throw ConfigurationError.invalid("SCP 已取消，续传文件已保留。") }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        // Drain stderr independently so progress polling cannot block the subprocess.
        final class Capture: @unchecked Sendable { var message = Data() }
        let capture = Capture(), drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { drained.leave() }
            while let bytes = try? errors.fileHandleForReading.read(upToCount: 4096), !bytes.isEmpty {
                if capture.message.count < 16384 { capture.message.append(bytes) }
            }
        }
        while child.isRunning {
            progress?()
            Thread.sleep(forTimeInterval: 0.25)
        }
        child.waitUntilExit()
        drained.wait()
        try? errors.fileHandleForReading.close()
        progress?()
        lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
        guard !wasCancelled, child.terminationStatus == 0 else {
            throw ConfigurationError.invalid("SCP 未完成，重新选择同一文件可通过 SFTP 续传。\n" + String(decoding: capture.message, as: UTF8.self))
        }
    }
}
