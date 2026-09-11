import Foundation

public struct SessionHistory: Codable, Identifiable, Equatable {
    public let id: UUID
    public let label: String
    public let started: Date
    public let updated: Date
    public let text: String
    public init(id: UUID, label: String, started: Date, updated: Date = Date(), text: String) {
        self.id = id; self.label = label; self.started = started; self.updated = updated; self.text = text
    }
}

/// Each session is an independent atomic archive; no shared index can overwrite other records.
public struct HistoryRepository {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ history: SessionHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(history)
        let url = directory.appendingPathComponent(history.id.uuidString + ".json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func ids() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }
    public func load(_ id: UUID) throws -> SessionHistory {
        let record = try JSONDecoder().decode(SessionHistory.self, from: Data(contentsOf: directory.appendingPathComponent(id.uuidString + ".json")))
        guard record.id == id else { throw ConfigurationError.invalid("会话历史编号不匹配。") }
        return record
    }
    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
    }
    public static func export(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
