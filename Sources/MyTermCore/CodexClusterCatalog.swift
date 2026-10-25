import Foundation

public struct CodexCluster: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let folder: String
    public var directory: String? = nil
}
public struct CodexClusterConversation: Codable, Identifiable, Equatable {
    public let id: String
    public let clusterID: UUID
    public var title: String
    public var lastOpened: Date
    public init(id: String, clusterID: UUID, title: String, lastOpened: Date) {
        self.id = id; self.clusterID = clusterID; self.title = title; self.lastOpened = lastOpened
    }
}
/// Stores MyTerm's organization only. Codex owns transcripts, authentication and titles.
public struct CodexClusterCatalog: Codable {
    public var version = 1
    public var projectsDirectory: String? = nil
    public var clusters: [CodexCluster] = []
    public var conversations: [CodexClusterConversation] = []
    public var serverClusters: [String: UUID] = [:]
    public init() {}
    public static func validatedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConfigurationError.invalid("名称需为 1–100 个字符，不能包含控制字符。")
        }
        return name
    }
    public mutating func addCluster(_ input: String) throws -> CodexCluster {
        let name = try Self.validatedName(input)
        if let existing = clusters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        guard clusters.count < 500 else { throw ConfigurationError.invalid("集群数量已达上限。") }
        let id = UUID()
        let safe = name.map { "/\\:".contains($0) ? "-" : $0 }
        let cluster = CodexCluster(id: id, name: name, folder: String(safe.prefix(40)) + "-" + id.uuidString.prefix(8))
        clusters.append(cluster)
        return cluster
    }
    /// Pin existing paths before changing the default; Codex histories retain their original cwd.
    public mutating func setProjectsDirectory(_ directory: String?, defaultDirectory: URL) throws {
        if let directory { try Self.validateDirectory(directory) }
        for i in clusters.indices {
            clusters[i].directory = directoryURL(for: clusters[i], defaultDirectory: defaultDirectory).path
        }
        projectsDirectory = directory
    }
    public func directoryURL(for cluster: CodexCluster, defaultDirectory: URL) -> URL {
        if let path = cluster.directory { return URL(fileURLWithPath: path) }
        return (projectsDirectory.map { URL(fileURLWithPath: $0) } ?? defaultDirectory).appendingPathComponent(cluster.folder)
    }
    private static func validateDirectory(_ path: String) throws {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConfigurationError.invalid("集群工作目录必须是有效的绝对路径。")
        }
    }
    public mutating func removeConversation(_ id: String, openThreads: Set<String>) throws {
        guard !openThreads.contains(id) else { throw ConfigurationError.invalid("请先关闭该对话的 Codex 标签。") }
        conversations.removeAll { $0.id == id }
    }
    public mutating func removeCluster(_ id: UUID, openThreads: Set<String>) throws {
        guard !conversations.contains(where: { $0.clusterID == id && openThreads.contains($0.id) }) else {
            throw ConfigurationError.invalid("请先关闭该集群的 Codex 标签。")
        }
        conversations.removeAll { $0.clusterID == id }
        serverClusters = serverClusters.filter { $0.value != id }
        clusters.removeAll { $0.id == id }
    }
    public func uniqueTitle(_ input: String, cluster: UUID, now: Date = Date()) throws -> String {
        let base = try Self.validatedName(input)
        let used = Set(conversations.filter { $0.clusterID == cluster }.map(\.title))
        if !used.contains(base) { return base }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        let timestamped = base + " · " + formatter.string(from: now)
        if !used.contains(timestamped) { return timestamped }
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        let precise = base + " · " + formatter.string(from: now)
        if !used.contains(precise) { return precise }
        throw ConfigurationError.invalid("无法生成唯一对话名称。")
    }
    public func validate() throws {
        guard version == 1, clusters.count <= 500, conversations.count <= 10000,
              Set(clusters.map(\.id)).count == clusters.count,
              Set(conversations.map(\.id)).count == conversations.count else { throw ConfigurationError.invalid("集群对话索引格式无效。") }
        if let projectsDirectory { try Self.validateDirectory(projectsDirectory) }
        for cluster in clusters {
            if let directory = cluster.directory { try Self.validateDirectory(directory) }
            _ = try Self.validatedName(cluster.name)
            guard !cluster.folder.isEmpty, !cluster.folder.contains("/"), !cluster.folder.contains("\\"),
                  cluster.folder != ".", cluster.folder != ".." else { throw ConfigurationError.invalid("集群目录无效。") }
        }
        for conversation in conversations {
            guard UUID(uuidString: conversation.id) != nil, clusters.contains(where: { $0.id == conversation.clusterID }),
                  !conversation.title.isEmpty, conversation.title.count <= 1024 else { throw ConfigurationError.invalid("集群对话索引格式无效。") }
        }
    }
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.intValue <= 8 * 1048576 else { throw ConfigurationError.invalid("集群对话索引过大。") }
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
    public func save(to url: URL) throws {
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct CodexConversationLaunch {
    public let threadID: String
    public let directory: String
    public let label: String
    public let isNew: Bool
    public init(threadID: String, directory: String, label: String, isNew: Bool) {
        self.threadID = threadID; self.directory = directory; self.label = label; self.isNew = isNew
    }
}
