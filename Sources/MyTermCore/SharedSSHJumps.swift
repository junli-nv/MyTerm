import Foundation

/// In memory each reference carries a resolved snapshot for existing connection/archive APIs.
/// On disk definitions are stored once; per-session rows contain only IDs.
public enum SharedSSHJumps {
    public struct Reference: Codable { let rowID: UUID; let profileID: UUID }
    public struct Entry: Codable { var server: Server; let jumps: [Reference]? }
    public struct Document: Codable {
        let version: Int
        let profiles: [SSHJumpServer]
        let entries: [Entry]
    }
    private static func definition(_ hop: SSHJumpServer) throws -> SSHJumpServer {
        var value = try hop.validated()
        value.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        value.profileID = nil
        return value
    }
    public static func sameDefinition(_ lhs: SSHJumpServer, _ rhs: SSHJumpServer) -> Bool {
        guard let left = try? definition(lhs), let right = try? definition(rhs) else { return false }
        return left == right
    }
    /// Only identical definitions on identical routes are automatically merged.
    /// Selecting a shared profile explicitly may reuse it on a different route.
    public static func normalized(_ servers: [Server]) throws -> [Server] {
        var profiles: [UUID: SSHJumpServer] = [:]
        var candidates: [Data: UUID] = [:]
        var ambiguous = Set<Data>()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        struct Key: Codable { let hops: [SSHJumpServer]; let proxy: NetworkProxy? }
        // Existing IDs take precedence over unlinked legacy copies.
        for server in servers {
            for hop in server.jumpServers ?? [] {
                if let id = hop.profileID {
                    if let old = profiles[id], !sameDefinition(old, hop) {
                        throw ConfigurationError.invalid("公共跳板机引用的配置不一致，未保存任何更改。")
                    }
                    profiles[id] = hop
                }
            }
        }
        func key(_ server: Server, _ index: Int) throws -> Data {
            try encoder.encode(Key(hops: try server.jumpServers!.prefix(index + 1).map(definition), proxy: server.proxy))
        }
        for server in servers {
            for (index, hop) in (server.jumpServers ?? []).enumerated() {
                if let id = hop.profileID {
                    let route = try key(server, index)
                    if let old = candidates[route], old != id { ambiguous.insert(route) }
                    candidates[route] = id
                }
            }
        }
        return try servers.map { original in
            var server = try original.validated()
            for index in (server.jumpServers ?? []).indices {
                var hop = server.jumpServers![index]
                if hop.profileID == nil {
                    let route = try key(server, index)
                    let id = ambiguous.contains(route) ? UUID() : (candidates[route] ?? UUID())
                    candidates[route] = id; hop.profileID = id
                }
                server.jumpServers![index] = hop
            }
            return server
        }
    }
    public static func encode(_ servers: [Server], profiles retained: [SSHJumpServer] = []) throws -> Data {
        let normalized = try normalized(servers)
        guard Set(retained.map(\.id)).count == retained.count else { throw ConfigurationError.invalid("公共跳板机编号重复。") }
        var profiles: [UUID: SSHJumpServer] = [:]
        for original in retained {
            var profile = try original.validated(); profile.profileID = nil
            profiles[profile.id] = profile
        }
        let entries = normalized.map { original -> Entry in
            var server = original
            let refs = server.jumpServers?.map { hop -> Reference in
                let id = hop.profileID!
                var profile = hop; profile.id = id; profile.profileID = nil
                profiles[id] = profile
                return Reference(rowID: hop.id, profileID: id)
            }
            server.jumpServers = nil
            return Entry(server: server, jumps: refs)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: 2, profiles: profiles.values.sorted { $0.id.uuidString < $1.id.uuidString }, entries: entries))
    }
    public static func profiles(in data: Data) throws -> [SSHJumpServer] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 2, Set(document.profiles.map(\.id)).count == document.profiles.count else {
            throw ConfigurationError.invalid("公共跳板机配置版本不支持或编号重复。")
        }
        return try document.profiles.map { original in
            var profile = try original.validated(); profile.profileID = profile.id; return profile
        }
    }
    public static func decode(_ data: Data) throws -> [Server] {
        _ = try profiles(in: data)
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 2, Set(document.profiles.map(\.id)).count == document.profiles.count else {
            throw ConfigurationError.invalid("公共跳板机配置版本不支持或编号重复。")
        }
        let profiles = Dictionary(uniqueKeysWithValues: document.profiles.map { ($0.id, $0) })
        return try document.entries.map { entry in
            var server = entry.server
            server.jumpServers = try entry.jumps?.map { ref in
                guard var hop = profiles[ref.profileID] else { throw ConfigurationError.invalid("会话引用的公共跳板机不存在，原文件已保留。") }
                hop.id = ref.rowID; hop.profileID = ref.profileID
                return try hop.validated()
            }
            return try server.validated()
        }
    }
    /// Update all references together. Runtime SSH transports keep their original snapshot.
    public static func applying(_ edited: Server, to servers: [Server]) -> [Server] {
        let changes = Dictionary((edited.jumpServers ?? []).compactMap { hop in hop.profileID.map { ($0, hop) } }, uniquingKeysWith: { _, last in last })
        var result = servers.map { current -> Server in
            var server = current.id == edited.id ? edited : current
            server.jumpServers = server.jumpServers?.map { hop in
                guard let id = hop.profileID, var update = changes[id] else { return hop }
                update.id = hop.id; return update
            }
            return server
        }
        if !result.contains(where: { $0.id == edited.id }) { result.append(edited) }
        return result
    }
    public static func resolving(_ server: Server, from current: [Server], profiles catalog: [SSHJumpServer] = []) -> Server {
        var result = server
        let profiles = catalog + current.flatMap { $0.jumpServers ?? [] }
        result.jumpServers = result.jumpServers?.map { hop in
            let linkedID = hop.profileID ?? current.first(where: { $0.id == server.id })?.jumpServers?.first(where: { $0.id == hop.id })?.profileID
            guard let id = linkedID, var current = profiles.first(where: { $0.profileID == id }) else { return hop }
            current.id = hop.id; return current
        }
        return result
    }
}
