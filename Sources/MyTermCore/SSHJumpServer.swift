import Foundation

/// Authentication belongs to each hop. Passwords remain in the encrypted credential store.
public struct SSHJumpServer: Codable, Equatable, Identifiable {
    public var id: UUID
    public var host: String
    public var port: String
    public var user: String
    public var identityFile: String
    public var authentication: AuthenticationMode
    public init(id: UUID = UUID(), host: String = "", port: String = "22", user: String = "", identityFile: String = "", authentication: AuthenticationMode = .automatic) {
        self.id = id; self.host = host; self.port = port; self.user = user
        self.identityFile = identityFile; self.authentication = authentication
    }
    public func validated() throws -> Self {
        let server = try Server(host: host, user: user, port: port, identityFile: identityFile).validated()
        var result = self
        result.host = server.host; result.port = server.port; result.user = server.user; result.identityFile = server.identityFile
        guard !result.identityFile.contains("\r") else { throw ConfigurationError.invalid("密钥文件路径无效。") }
        return result
    }
}

extension Server {
    public var effectiveJumpHost: String? {
        guard let jumpServers, !jumpServers.isEmpty else { return jumpHost }
        return jumpServers.indices.map { jumpAlias($0) }.joined(separator: ",")
    }
    private func jumpAlias(_ index: Int) -> String { "myterm-hop-\(id.uuidString.lowercased())-\(index + 1)" }

    func detailedJumpConfig(userConfig: String) throws -> String? {
        guard let jumps = jumpServers, !jumps.isEmpty else { return nil }
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        var blocks: [String] = []
        for (index, original) in jumps.enumerated() {
            let hop = try original.validated()
            var lines = ["Host \(jumpAlias(index))", "    HostName \(quote(hop.host))", "    Port \(hop.port.isEmpty ? "22" : hop.port)",
                         "    ProxyJump none", "    ForwardAgent no", "    ForwardX11 no", "    ControlMaster no", "    ControlPath none",
                         "    ServerAliveInterval 30", "    ServerAliveCountMax 6", "    TCPKeepAlive yes",
                         "    Compression \(compression ?? true ? "yes" : "no")"]
            if !hop.user.isEmpty { lines.append("    User \(quote(hop.user))") }
            if !hop.identityFile.isEmpty {
                lines += ["    IdentityFile \(quote((hop.identityFile as NSString).expandingTildeInPath))", "    IdentitiesOnly yes"]
            }
            switch hop.authentication {
            case .automatic: break
            case .password:
                lines += ["    PubkeyAuthentication no", "    PasswordAuthentication yes", "    KbdInteractiveAuthentication yes", "    PreferredAuthentications keyboard-interactive,password"]
            case .key:
                lines += ["    PubkeyAuthentication yes", "    PasswordAuthentication no", "    KbdInteractiveAuthentication no", "    PreferredAuthentications publickey"]
            }
            if debugLogging == true { lines.append("    LogLevel DEBUG3") }
            lines.append("    ProxyCommand \(index == 0 ? try proxy?.command() ?? "none" : "none")")
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n") + "\nHost *\n    Include \(quote(userConfig))\n    Include /etc/ssh/ssh_config\n"
    }
}
