import Foundation

public struct SessionTab: Codable, Equatable {
    public var server: Server?
    public var directory: String?
    public var historyLogging: HistoryLoggingMode?
    public var encoding: TerminalEncoding?
    public init(server: Server? = nil, directory: String? = nil, encoding: TerminalEncoding? = nil, historyLogging: HistoryLoggingMode? = nil) {
        self.server = server; self.directory = directory; self.encoding = encoding; self.historyLogging = historyLogging
    }
}

public struct SavedSession: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var tabs: [SessionTab]
    public var selectedIndex: Int
    public init(id: UUID = UUID(), name: String, tabs: [SessionTab], selectedIndex: Int) {
        self.id = id; self.name = name; self.tabs = tabs; self.selectedIndex = selectedIndex
    }
}

public struct SessionRepository {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SavedSession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let sessions = try JSONDecoder().decode([SavedSession].self, from: Data(contentsOf: url))
        guard Set(sessions.map(\.id)).count == sessions.count else { throw ConfigurationError.invalid("保存的会话 ID 重复。") }
        for session in sessions {
            guard !session.tabs.isEmpty, session.tabs.count <= 100, session.tabs.indices.contains(session.selectedIndex) else {
                throw ConfigurationError.invalid("保存的会话标签或选中位置无效。")
            }
            for tab in session.tabs { if let server = tab.server { _ = try server.validated() } }
        }
        return sessions
    }
    public func save(_ sessions: [SavedSession]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
