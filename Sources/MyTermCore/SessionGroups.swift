import Foundation

public struct SessionGroup: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var serverIDs: [UUID]
    public var collapsed: Bool
    public init(id: UUID = UUID(), name: String, serverIDs: [UUID] = [], collapsed: Bool = false) {
        self.id = id; self.name = name; self.serverIDs = serverIDs; self.collapsed = collapsed
    }
    /// Treat pasted line separators as spaces and discard invisible input artifacts.
    public static func normalizedName(_ input: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || scalar == "\t" {
                result.append(" ")
            } else if !CharacterSet.controlCharacters.contains(scalar) {
                result.append(scalar)
            }
        }
        return String(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
public struct SessionGroupRepository {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func validate(_ groups: [SessionGroup]) throws {
        var ids = Set<UUID>(), names = Set<String>(), members = Set<UUID>()
        for group in groups {
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ConfigurationError.invalid("请输入分组名称，不能只包含空格。") }
            guard name.count <= 60 else { throw ConfigurationError.invalid("分组名称不能超过 60 个字符。") }
            // Keep the receiver inside the closure: the bound Foundation method reference
            // misclassifies ordinary names in the optimized build with the current toolchain.
            guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigurationError.invalid("分组名称不能包含换行、制表符或其他控制字符。")
            }
            guard name != "未分组" else { throw ConfigurationError.invalid("‘未分组’是保留名称，请换一个名称。") }
            guard ids.insert(group.id).inserted, names.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted else {
                throw ConfigurationError.invalid("分组名称或编号重复。")
            }
            for id in group.serverIDs where !members.insert(id).inserted {
                throw ConfigurationError.invalid("同一服务器不能属于多个分组。")
            }
        }
    }
    public func load() throws -> [SessionGroup] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let groups = try JSONDecoder().decode([SessionGroup].self, from: Data(contentsOf: url))
        try Self.validate(groups); return groups
    }
    /// Groups are optional at startup. Explicit imports/restores still use strict loading.
    public func loadForStartup() -> [SessionGroup] {
        if let groups = try? load() { return groups }
        guard let data = try? Data(contentsOf: url),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        struct LegacyGroup: Decodable {
            var id: UUID?
            var name: String
            var serverIDs: [UUID]?
            var collapsed: Bool?
        }
        var groups: [SessionGroup] = [], members = Set<UUID>()
        for row in rows {
            guard JSONSerialization.isValidJSONObject(row),
                  let bytes = try? JSONSerialization.data(withJSONObject: row),
                  let record = try? JSONDecoder().decode(LegacyGroup.self, from: bytes) else { continue }
            var group = SessionGroup(id: record.id ?? UUID(), name: SessionGroup.normalizedName(record.name), collapsed: record.collapsed ?? false)
            var seen = members
            group.serverIDs = (record.serverIDs ?? []).filter { seen.insert($0).inserted }
            guard (try? Self.validate(groups + [group])) != nil else { continue }
            groups.append(group); members = seen
        }
        return groups
    }
    public func save(_ groups: [SessionGroup]) throws {
        try Self.validate(groups)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(groups)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Preserve unreadable/invalid original data before the first edit after recovery.
        if FileManager.default.fileExists(atPath: url.path), (try? load()) == nil {
            let backup = url.deletingLastPathComponent().appendingPathComponent("groups-recovery-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: backup)
        }
        try data.write(to: url, options: .atomic)
    }
    /// Remove the active group file without destroying the user's recovery copy.
    public func removePreservingOriginal() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backup = url.deletingLastPathComponent().appendingPathComponent("groups-recovery-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: url, to: backup)
    }
    public static func moving(_ server: UUID, to group: UUID?, in groups: [SessionGroup]) throws -> [SessionGroup] {
        guard group == nil || groups.contains(where: { $0.id == group }) else { throw ConfigurationError.invalid("目标分组不存在。") }
        var updated = groups
        for index in updated.indices {
            updated[index].serverIDs.removeAll { $0 == server }
            if updated[index].id == group { updated[index].serverIDs.append(server) }
        }
        try validate(updated); return updated
    }
}
