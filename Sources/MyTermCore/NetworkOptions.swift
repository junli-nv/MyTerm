import Foundation

public enum AuthenticationMode: String, Codable, CaseIterable { case automatic, password, key }
public enum ProxyKind: String, Codable, CaseIterable { case http, socks5 }
public struct NetworkProxy: Codable, Equatable {
    public var kind: ProxyKind
    public var host: String
    public var port: String
    public init(kind: ProxyKind = .socks5, host: String = "127.0.0.1", port: String = "7890") {
        self.kind = kind; self.host = host; self.port = port
    }
    public func command() throws -> String {
        _ = try Server(host: host, port: port).validated()
        guard !port.isEmpty, !host.contains("%") else { throw ConfigurationError.invalid("请填写代理端口及有效地址。") }
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("MyTermProxy").path
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return "\(quote(helper)) \(kind.rawValue) \(quote(host)) \(quote(port)) '%h' '%p'"
    }
}

public enum ForwardKind: String, Codable, CaseIterable { case local, remote, dynamic }
public struct PortForward: Identifiable, Codable, Equatable {
    public var id: UUID
    public var kind: ForwardKind
    public var bindAddress: String
    public var listenPort: String
    public var destinationHost: String
    public var destinationPort: String
    public init(id: UUID = UUID(), kind: ForwardKind = .local, bindAddress: String = "127.0.0.1", listenPort: String = "8080", destinationHost: String = "127.0.0.1", destinationPort: String = "80") {
        self.id = id; self.kind = kind; self.bindAddress = bindAddress; self.listenPort = listenPort
        self.destinationHost = destinationHost; self.destinationPort = destinationPort
    }
    public func arguments() throws -> [String] {
        func endpoint(_ host: String, _ port: String) throws -> String {
            _ = try Server(host: host, port: port).validated()
            guard !port.isEmpty, !host.contains("%") else { throw ConfigurationError.invalid("端口转发需要有效地址和端口。") }
            return "\(host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host):\(port)"
        }
        let listener = try endpoint(bindAddress, listenPort)
        if kind == .dynamic { return ["-D", listener] }
        return [kind == .local ? "-L" : "-R", listener + ":" + (try endpoint(destinationHost, destinationPort))]
    }
}

/// Per-session private socket/config directory; the original SSH config remains read-only.
public final class SSHLaunchContext {
    public let directory: URL
    public var controlPath: String { directory.appendingPathComponent("control").path }
    public let configPath: String?

    public init(server: Server) throws {
        directory = URL(fileURLWithPath: "/tmp").appendingPathComponent("myterm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            if let content = try server.proxyJumpConfig() {
                let file = directory.appendingPathComponent("ssh_config")
                try Data(content.utf8).write(to: file, options: .atomic)
                configPath = file.path
            } else { configPath = nil }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
