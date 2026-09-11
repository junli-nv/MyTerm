import Foundation

public enum X11Forwarding: String, Codable, CaseIterable { case disabled, untrusted, trusted }

public struct Server: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String
    public var port: String
    public var identityFile: String
    public var jumpHost: String?
    public var jumpServers: [SSHJumpServer]?
    public var compression: Bool?
    public var proxy: NetworkProxy?
    public var forwards: [PortForward]?
    public var authentication: AuthenticationMode?
    public var x11Forwarding: X11Forwarding?
    public var debugLogging: Bool?
    public var trzszEnabled: Bool?
    public var dragUploadProtocol: DragUploadProtocol?

    public init(id: UUID = UUID(), name: String = "", host: String = "", user: String = "", port: String = "", identityFile: String = "", jumpHost: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.jumpHost = jumpHost
    }

    public var displayName: String { name.isEmpty ? host : name }

    public func validated() throws -> Server {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        result.user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        result.port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        result.identityFile = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:%[]")
        guard !result.host.isEmpty, !result.host.hasPrefix("-"), result.host.unicodeScalars.allSatisfy(hostCharacters.contains) else {
            throw ConfigurationError.invalid("主机请填写域名、IP 地址或 SSH 配置别名，不要包含用户名或命令。")
        }
        if !result.user.isEmpty {
            let userCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@\\")
            guard !result.user.hasPrefix("-"), result.user.unicodeScalars.allSatisfy(userCharacters.contains) else {
                throw ConfigurationError.invalid("用户名包含不支持的字符。")
            }
        }
        if !result.port.isEmpty {
            guard let number = Int(result.port), (1...65535).contains(number) else {
                throw ConfigurationError.invalid("端口必须在 1–65535 之间。")
            }
        }
        guard !result.identityFile.contains("\n"), !result.identityFile.contains("\0") else {
            throw ConfigurationError.invalid("密钥文件路径无效。")
        }
        if let jump = jumpHost?.trimmingCharacters(in: .whitespacesAndNewlines), !jump.isEmpty {
            try Self.validateJump(jump)
            result.jumpHost = jump
        } else { result.jumpHost = nil }
        if let jumps = jumpServers {
            guard !jumps.isEmpty, jumps.count <= 10 else { throw ConfigurationError.invalid("请配置 1–10 台跳板机。") }
            guard result.jumpHost == nil else { throw ConfigurationError.invalid("详细跳板机设置不能与跳板别名同时使用。") }
            result.jumpServers = try jumps.map { try $0.validated() }
            guard Set(jumps.map(\.id)).count == jumps.count else { throw ConfigurationError.invalid("跳板机编号重复。") }
        }
        if let proxy = result.proxy { _ = try proxy.command() }
        var listeners = Set<String>()
        for forward in result.forwards ?? [] {
            _ = try forward.arguments()
            let key = "\(forward.kind == .remote ? "remote" : "local"):\(forward.bindAddress):\(forward.listenPort)"
            guard listeners.insert(key).inserted else { throw ConfigurationError.invalid("端口转发存在重复监听端口。") }
        }
        return result
    }

    private static func validateJump(_ jump: String) throws {
        if jump == "none" { return }
        let pattern = #"^(?:[A-Za-z0-9_.][A-Za-z0-9_.-]*@)?(?:[A-Za-z0-9_][A-Za-z0-9_.-]*|\[[A-Fa-f0-9:%]+\])(?::([0-9]+))?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        for part in jump.split(separator: ",", omittingEmptySubsequences: false) {
            let value = String(part)
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, range: range), match.range == range else {
                throw ConfigurationError.invalid("跳板机请填写 SSH 别名或 user@host:port，多级跳板用逗号分隔。")
            }
            if let portRange = Range(match.range(at: 1), in: value) {
                guard let port = Int(value[portRange]), (1...65535).contains(port) else {
                    throw ConfigurationError.invalid("跳板机端口必须在 1–65535 之间。")
                }
            }
        }
    }

    /// Pass arguments directly to exec: never interpolate configuration into a shell command.
    public func connectionArguments(configPath: String? = nil) throws -> [String] {
        let server = try validated()
        var args = ["-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=6", "-o", "TCPKeepAlive=yes"]
        args += ["-o", "Compression=\(server.compression ?? true ? "yes" : "no")"]
        do {
            let x11 = server.x11Forwarding ?? .disabled
            args += ["-o", "ForwardX11=\(x11 == .disabled ? "no" : "yes")"]
            if x11 != .disabled {
                args += ["-o", "ForwardX11Trusted=\(x11 == .trusted ? "yes" : "no")"]
                if FileManager.default.isExecutableFile(atPath: "/opt/X11/bin/xauth") { args += ["-o", "XAuthLocation=/opt/X11/bin/xauth"] }
            }
        }
        if let configPath { args += ["-F", configPath] }
        switch server.authentication ?? .automatic {
        case .automatic: break
        case .password: args += ["-o", "PubkeyAuthentication=no", "-o", "PasswordAuthentication=yes", "-o", "KbdInteractiveAuthentication=yes", "-o", "PreferredAuthentications=keyboard-interactive,password"]
        case .key: args += ["-o", "PubkeyAuthentication=yes", "-o", "PreferredAuthentications=publickey", "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no"]
        }
        if let proxy = server.proxy, server.effectiveJumpHost == nil || server.effectiveJumpHost == "none" {
            args += ["-o", "ProxyCommand=\(try proxy.command())"]
        }
        if !server.port.isEmpty { args += ["-p", server.port] }
        if !server.user.isEmpty { args += ["-l", server.user] }
        if !server.identityFile.isEmpty {
            args += ["-i", (server.identityFile as NSString).expandingTildeInPath]
        }
        if let jump = server.effectiveJumpHost { args += ["-J", jump] }
        return args
    }

    public func sshArguments(controlPath: String? = nil, configPath: String? = nil) throws -> [String] {
        var args = ["-tt"]
        if debugLogging == true { args.append("-vvv") }
        if let controlPath {
            args += ["-o", "ControlMaster=auto", "-o", "ControlPersist=no", "-o", "ControlPath=\(controlPath)"]
        }
        if !(forwards ?? []).isEmpty {
            args += ["-o", "ExitOnForwardFailure=yes"]
            for forward in forwards ?? [] { args += try forward.arguments() }
        }
        return args + (try connectionArguments(configPath: configPath)) + ["--", try validated().host]
    }

    public func sftpArguments(controlPath: String, configPath: String? = nil) throws -> [String] {
        // -s starts the SFTP subsystem directly; binary protocol travels over pipes, never a PTY.
        ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ControlMaster=no",
         "-o", "ControlPath=\(controlPath)", "-o", "ClearAllForwardings=yes", "-o", "RemoteCommand=none",
         "-s"] + (try connectionArguments(configPath: configPath)) + ["--", try validated().host, "sftp"]
    }

    public func proxyJumpConfig(userConfig: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config").path) throws -> String? {
        if let detailed = try detailedJumpConfig(userConfig: userConfig) { return detailed }
        guard let proxy, let jumpHost, jumpHost != "none", !jumpHost.isEmpty else { return nil }
        try Self.validateJump(jumpHost)
        let first = String(jumpHost.split(separator: ",")[0].split(separator: "@").last!)
        let firstHost: String
        if first.hasPrefix("[") { firstHost = String(first.dropFirst().prefix { $0 != "]" }) }
        else { firstHost = String(first.split(separator: ":")[0]) }
        guard firstHost != host else { throw ConfigurationError.invalid("目标与第一台跳板机不能使用相同主机别名。") }
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return "Host \(firstHost)\n    ProxyCommand \(try proxy.command())\nHost *\n    Include \(quote(userConfig))\n    Include /etc/ssh/ssh_config\n"
    }

}

public enum ConfigurationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public struct ServerRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> [Server] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let servers = try JSONDecoder().decode([Server].self, from: Data(contentsOf: fileURL))
        guard Set(servers.map(\.id)).count == servers.count else {
            throw ConfigurationError.invalid("服务器配置包含重复 ID。")
        }
        return try servers.map { try $0.validated() }
    }

    public func save(_ servers: [Server]) throws {
        let validated = try servers.map { try $0.validated() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
