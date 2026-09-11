import Foundation

public enum HistoryLoggingMode: String, Codable, CaseIterable {
    case inherit, enabled, disabled
    public func resolves(global: Bool) -> Bool {
        switch self { case .inherit: return global; case .enabled: return true; case .disabled: return false }
    }
    public var title: String {
        switch self { case .inherit: return "跟随全局设置"; case .enabled: return "始终保存日志"; case .disabled: return "不保存日志" }
    }
}

public struct HistoryPolicy: Codable, Equatable {
    public var compressed = true
    public var enabled = false
    public var maximumLines = 50_000
    public var fileMiB = 20
    public var totalMiB = 500
    public init() {}
    public func validate() throws {
        guard (100...1_000_000).contains(maximumLines), (1...1024).contains(fileMiB),
              (1...102_400).contains(totalMiB), fileMiB <= totalMiB else {
            throw ConfigurationError.invalid("历史限制无效：行数 100–1,000,000，单文件 1–1,024 MiB，总容量 1–102,400 MiB，且总容量不能小于单文件。")
        }
    }
    /// Limits include the JSON envelope, escaped characters and UTF-8 encoding.
    public func archiveData(_ record: SessionHistory) throws -> Data {
        try validate()
        let lines = record.text.split(separator: "\n", omittingEmptySubsequences: false)
        let trailing = lines.last?.isEmpty == true ? 1 : 0
        let text = lines.suffix(maximumLines + trailing).joined(separator: "\n")
        let limit = fileMiB * 1024 * 1024
        var retained = text
        while true {
            let raw = try JSONEncoder().encode(SessionHistory(id: record.id, label: record.label, started: record.started, updated: record.updated, text: retained))
            let actual: Int, target: Int
            if raw.count > HistoryCompression.expandedLimit {
                actual = raw.count; target = HistoryCompression.expandedLimit
            } else {
                let data = compressed ? try HistoryCompression.transform(raw, compress: true) : raw
                if data.count <= limit { return data }
                actual = data.count; target = limit
            }
            guard !retained.isEmpty else { throw ConfigurationError.invalid("历史记录标题超过文件限制。") }
            // Estimate a smaller suffix instead of repeatedly compressing a binary search.
            // UTF-8 indices avoid an enormous Array<Character> for large histories.
            let bytes = retained.utf8
            let keep = min(bytes.count - 1, Int(Double(bytes.count) * Double(target) / Double(actual) * 0.95))
            var start = bytes.index(bytes.endIndex, offsetBy: -max(0, keep))
            while start != bytes.endIndex && String.Index(start, within: retained) == nil { bytes.formIndex(after: &start) }
            retained = String(retained[String.Index(start, within: retained)!...])
        }
    }
}

extension HistoryRepository {
    public func save(_ history: SessionHistory, policy: HistoryPolicy, shouldWrite: () -> Bool = { true }) throws {
        guard policy.enabled else { return }
        let data = try policy.archiveData(history)
        guard shouldWrite() else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(history.id.uuidString + (policy.compressed ? ".json.gz" : ".json"))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let previous = directory.appendingPathComponent(history.id.uuidString + (policy.compressed ? ".json" : ".json.gz"))
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
    }
    /// Only UUID-named history JSON files are eligible; unrelated files are untouched.
    public func clean(before: Date? = nil) throws -> Set<UUID> {
        var deleted = Set<UUID>()
        for id in try ids() {
            let date = try recordFiles(id).map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast }.max() ?? .distantPast
            if before == nil || date < before! { try delete(id); deleted.insert(id) }
        }
        return deleted
    }
    public func enforceCapacity(_ policy: HistoryPolicy) throws {
        try policy.validate()
        var files: [(UUID, Int, Date)] = []
        for id in try ids() {
            let values = try recordFiles(id).map { try $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) }
            files.append((id, values.reduce(0) { $0 + ($1.fileSize ?? 0) }, values.compactMap(\.contentModificationDate).max() ?? .distantPast))
        }
        var size = files.reduce(0) { $0 + $1.1 }
        for file in files.sorted(by: { $0.2 < $1.2 }) where size > policy.totalMiB * 1024 * 1024 {
            try delete(file.0); size -= file.1
        }
    }
}
