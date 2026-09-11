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
        return Array(Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { url -> UUID? in
                let name = url.lastPathComponent
                if name.hasSuffix(".json.gz") { return UUID(uuidString: String(name.dropLast(8))) }
                if name.hasSuffix(".json") { return UUID(uuidString: String(name.dropLast(5))) }
                return nil
            }))
    }
    func recordFiles(_ id: UUID) -> [URL] {
        [".json.gz", ".json"].map { directory.appendingPathComponent(id.uuidString + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    public func load(_ id: UUID) throws -> SessionHistory {
        guard let url = recordFiles(id).first else { throw ConfigurationError.invalid("历史记录不存在。") }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= HistoryCompression.expandedLimit else { throw ConfigurationError.invalid("历史文件超过读取限制。") }
        let data = try Data(contentsOf: url)
        let decoded = url.pathExtension == "gz" ? try HistoryCompression.transform(data, compress: false) : data
        let record = try JSONDecoder().decode(SessionHistory.self, from: decoded)
        guard record.id == id else { throw ConfigurationError.invalid("会话历史编号不匹配。") }
        return record
    }
    public func delete(_ id: UUID) throws {
        for url in recordFiles(id) { try FileManager.default.removeItem(at: url) }
    }
    public static func export(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
