import Foundation

/// Portable configuration only: credentials and terminal output are deliberately separate.
public struct SessionArchive: Codable {
    public var version: Int = 1
    public var servers: [Server]
    public var groups: [SessionGroup]
    public var sessions: [SavedSession]
    public var jumpProfiles: [SSHJumpServer]?

    public init(servers: [Server], groups: [SessionGroup], sessions: [SavedSession], jumpProfiles: [SSHJumpServer]? = nil) {
        self.servers = servers; self.groups = groups; self.sessions = sessions; self.jumpProfiles = jumpProfiles
    }
    public func validate() throws {
        guard version == 1 else { throw ConfigurationError.invalid("不支持此会话文件版本。") }
        guard servers.count <= 10000, groups.count <= 10000, sessions.count <= 1000,
              Set(servers.map(\.id)).count == servers.count,
              Set(sessions.map(\.id)).count == sessions.count else {
            throw ConfigurationError.invalid("会话文件记录过多或编号重复。")
        }
        for server in servers { _ = try server.validated() }
        guard (jumpProfiles?.count ?? 0) <= 10000 else { throw ConfigurationError.invalid("公共跳板机数量过多。") }
        _ = try SharedSSHJumps.encode(servers, profiles: jumpProfiles ?? [])
        for profile in jumpProfiles ?? [] {
            for hop in servers.flatMap({ $0.jumpServers ?? [] }) where hop.profileID == profile.id {
                guard SharedSSHJumps.sameDefinition(profile, hop) else { throw ConfigurationError.invalid("公共跳板机引用的配置不一致，未保存任何更改。") }
            }
        }
        try SessionGroupRepository.validate(groups)
        let ids = Set(servers.map(\.id))
        guard groups.allSatisfy({ Set($0.serverIDs).isSubset(of: ids) }) else {
            throw ConfigurationError.invalid("分组引用了不存在的服务器。")
        }
        for session in sessions {
            try session.validateLayouts()
            guard !session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !session.tabs.isEmpty, session.tabs.count <= 100,
                  session.tabs.indices.contains(session.selectedIndex) else {
                throw ConfigurationError.invalid("会话名称、标签数量或选中位置无效。")
            }
            for tab in session.tabs {
                if let server = tab.server { _ = try server.validated() }
                if let path = tab.directory, path.contains("\0") {
                    throw ConfigurationError.invalid("本地会话目录无效。")
                }
            }
        }
    }
    public static func decode(_ data: Data) throws -> SessionArchive {
        guard data.count <= 20 * 1024 * 1024 else { throw ConfigurationError.invalid("会话文件不能超过 20 MB。") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 20 * 1024 * 1024 else { throw ConfigurationError.invalid("会话文件不能超过 20 MB。") }
        return data
    }
    /// Repeat imports are idempotent. Conflicts reject the entire import before writing.
    public func merging(_ incoming: SessionArchive) throws -> SessionArchive {
        try validate(); try incoming.validate()
        func merge<T: Identifiable & Equatable>(_ existing: [T], _ additions: [T]) throws -> [T] {
            var result = existing
            for item in additions {
                if let old = existing.first(where: { $0.id == item.id }) {
                    guard old == item else { throw ConfigurationError.invalid("导入记录与现有配置编号相同但内容不同，未导入任何记录。请在另一份配置中删除冲突记录后重试。") }
                } else { result.append(item) }
            }
            return result
        }
        let result = try SessionArchive(servers: merge(servers, incoming.servers),
            groups: merge(groups, incoming.groups), sessions: merge(sessions, incoming.sessions),
            jumpProfiles: merge(jumpProfiles ?? [], incoming.jumpProfiles ?? []))
        try result.validate(); return result
    }
}
