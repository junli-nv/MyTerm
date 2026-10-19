import Foundation
import CryptoKit

/// Shared secrets identify a route, never a destination session or editor row UUID.
public enum SSHJumpCredentials {
    private struct Endpoint: Codable {
        let host: String
        let port: String
        let user: String
        init(_ hop: SSHJumpServer) {
            host = hop.host.lowercased(); port = hop.port.isEmpty ? "22" : hop.port; user = hop.user
        }
    }
    private struct Route: Codable {
        let hops: [Endpoint]
        let proxy: NetworkProxy?
    }
    public static func account(server: Server, index: Int) throws -> String {
        let hops = server.jumpServers ?? []
        guard hops.indices.contains(index), !hops[index].user.isEmpty else {
            throw ConfigurationError.invalid("保存跳板机密码前请填写用户名。")
        }
        let route = Route(hops: try hops.prefix(index + 1).map { Endpoint(try $0.validated()) }, proxy: server.proxy)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(route)).map { String(format: "%02x", $0) }.joined()
        return "jump-" + digest + ":password"
    }
    public static func accounts(server: Server) -> [String] {
        (server.jumpServers ?? []).indices.compactMap { try? account(server: server, index: $0) }
    }
    public static func label(_ hop: SSHJumpServer) -> String {
        (hop.editableName.isEmpty ? "SSH jump" : hop.displayName) + " · \(hop.user)@\(hop.host):\(hop.port.isEmpty ? "22" : hop.port)"
    }
    /// OpenSSH prompts omit the port. Ambiguous endpoints must remain interactive.
    public static func matchingIndex(prompt: String, server: Server) -> Int? {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(user: String, host: String) -> Bool {
            guard !user.isEmpty else { return false }
            return ["\(user)@\(host)'s password:", "\(user)@\(host)'s Password:",
                    "(\(user)@\(host)) Password:", "(\(user)@\(host)) password:"].contains(value)
        }
        guard !matches(user: server.user, host: server.host) else { return nil }
        let hops = server.jumpServers ?? []
        let matches = hops.indices.filter { index in
            matches(user: hops[index].user, host: hops[index].host)
                || matches(user: hops[index].user, host: "myterm-hop-\(server.id.uuidString.lowercased())-\(index + 1)")
        }
        guard matches.count == 1, let index = matches.first, hops[index].authentication != .key else { return nil }
        return index
    }
}

/// Public connection information only. New editor rows retain shared profile references.
public struct SSHJumpPreset: Identifiable {
    public let id: UUID
    public let name: String
    public let hops: [SSHJumpServer]
    public let proxy: NetworkProxy?
    public static func available(in servers: [Server]) -> [Self] {
        servers.compactMap { server in
            guard let hops = server.jumpServers, !hops.isEmpty else { return nil }
            return Self(id: server.id, name: server.displayName, hops: hops, proxy: server.proxy)
        }
    }
    public func copiedHops() -> [SSHJumpServer] {
        hops.map { hop in var copy = hop; copy.id = UUID(); return copy }
    }
}
