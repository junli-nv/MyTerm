import Foundation

public enum SSHConfigurationResolver {
    /// Resolve an inherited ProxyJump before adding an explicit network proxy.
    /// Call off the UI thread; unlike alias discovery this follows OpenSSH's Match evaluation.
    public static func resolvingJump(_ server: Server, configPath: String? = nil) throws -> Server {
        guard server.proxy != nil, server.effectiveJumpHost == nil else { return server }
        var probe = server; probe.proxy = nil; probe.forwards = nil
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-G"] + (try probe.connectionArguments(configPath: configPath)) + ["--", probe.host]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        // ssh -G output is small, but drain concurrently so large configs cannot block on a full pipe.
        final class Capture: @unchecked Sendable {
            let lock = NSLock(); var data = Data()
            func append(_ bytes: Data) { lock.lock(); if data.count < 4 * 1024 * 1024 { data.append(bytes) }; lock.unlock() }
        }
        let capture = Capture(), drained = DispatchSemaphore(value: 0)
        try process.run(); try? output.fileHandleForWriting.close()
        DispatchQueue.global(qos: .userInitiated).async {
            while let data = try? output.fileHandleForReading.read(upToCount: 32768), !data.isEmpty { capture.append(data) }
            drained.signal()
        }
        guard finished.wait(timeout: .now() + 10) == .success else {
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
            throw ConfigurationError.invalid("SSH 配置解析超时，请检查 Match exec 等配置。")
        }
        guard drained.wait(timeout: .now() + 2) == .success, process.terminationStatus == 0 else {
            try? output.fileHandleForReading.close()
            throw ConfigurationError.invalid("无法解析 SSH 配置，请检查主机别名。")
        }
        try? output.fileHandleForReading.close()
        var resolved = server
        for line in String(decoding: capture.data, as: UTF8.self).split(separator: "\n") where line.hasPrefix("proxyjump ") {
            let value = String(line.dropFirst(10))
            if value != "none" { resolved.jumpHost = value }
        }
        return try resolved.validated()
    }
}
