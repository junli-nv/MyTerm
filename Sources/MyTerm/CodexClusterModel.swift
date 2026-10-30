import Foundation
import SwiftUI
import MyTermCore

/// Main-thread catalog/UI state; blocking Codex metadata work runs off the UI thread.
final class CodexClusterModel: ObservableObject {
    @Published private(set) var catalog = CodexClusterCatalog()
    @Published private(set) var busy = false
    @Published var message = ""
    @Published private(set) var checks: [String: CodexConversationCheck] = [:]
    @Published private(set) var checkedAt: Date?
    private var refreshCancellation: Progress?
    private let root: URL
    private let index: URL
    private var loadFailed = false
    private(set) var cancelled = false
    func cancelLaunch() { cancelled = true; refreshCancellation?.cancel() }
    init(root: URL) {
        self.root = root; index = root.appendingPathComponent("codex-clusters.json")
        do { catalog = try CodexClusterCatalog.load(from: index) }
        catch { loadFailed = true; message = error.localizedDescription }
    }
    func add(_ name: String) -> UUID? {
        guard !loadFailed, !busy, !cancelled else { return nil }
        do {
            var next = catalog
            let cluster = try next.addCluster(name)
            try next.save(to: index); catalog = next; message = ""
            return cluster.id
        } catch { message = error.localizedDescription; return nil }
    }
    func defaultCluster() -> UUID? {
        var id: UUID?
        let saved = update { id = try $0.ensureDefaultCluster().id }
        return saved ? id : nil
    }
    var defaultDirectory: URL { root.appendingPathComponent("CodexProjects") }
    var projectsDirectory: URL { catalog.projectsDirectory.map { URL(fileURLWithPath: $0) } ?? defaultDirectory }
    func directory(for id: UUID) -> URL? {
        catalog.clusters.first(where: { $0.id == id }).map { catalog.directoryURL(for: $0, defaultDirectory: defaultDirectory) }
    }
    @discardableResult
    private func update(_ edit: (inout CodexClusterCatalog) throws -> Void) -> Bool {
        guard !busy, !loadFailed, !cancelled else { return false }
        do {
            var next = catalog; try edit(&next)
            try next.save(to: index); catalog = next; message = ""; return true
        } catch { message = error.localizedDescription; return false }
    }
    func setProjectsDirectory(_ url: URL?) {
        if let url {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue,
                  FileManager.default.isWritableFile(atPath: url.path) else {
                message = "请选择可写入的文件夹。"; return
            }
        }
        update { try $0.setProjectsDirectory(url?.standardizedFileURL.path, defaultDirectory: defaultDirectory) }
    }
    func removeConversation(_ id: String, openThreads: Set<String>) -> Bool {
        update { try $0.removeConversation(id, openThreads: openThreads) }
    }
    func removeCluster(_ id: UUID, openThreads: Set<String>) -> Bool {
        update { try $0.removeCluster(id, openThreads: openThreads) }
    }
    func renameCluster(_ id: UUID, name: String) {
        update { try $0.renameCluster(id, name: name) }
    }
    /// Explicit, metadata-only refresh. A shared deadline bounds even a very large catalog.
    func refresh(clusterID: UUID, bridge: CodexBridge) {
        guard !busy, !loadFailed, !cancelled, let directory = directory(for: clusterID) else { return }
        let records = conversations(in: clusterID)
        guard !records.isEmpty else { return }
        do {
            let executable = try bridge.executable()
            var environment = try bridge.saveConnection()
            let relay = try bridge.socksRelay()
            if let relay { environment = try relay.environment(base: environment) }
            let cancellation = Progress(totalUnitCount: Int64(records.count))
            refreshCancellation = cancellation
            busy = true; message = "正在刷新对话元数据…"
            for record in records { checks.removeValue(forKey: record.id) }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var results: [String: CodexConversationCheck] = [:]
                let deadline = ProcessInfo.processInfo.systemUptime + 30
                do {
                    let client = try CodexThreadClient(executable: executable, environment: environment, operationDeadline: deadline)
                    defer { client.close(); withExtendedLifetime(relay) {} }
                    var failure: String?
                    for record in records {
                        if cancellation.isCancelled { break }
                        if failure != nil {
                            results[record.id] = .unverified(reason: "前一项检查失败，本项未检查；请重试。")
                            continue
                        }
                        let result = CodexConversationCheck.read(id: record.id, directory: directory.path, client: client)
                        results[record.id] = result
                        // Stop on an ambiguous error rather than repeatedly hammering a broken host.
                        if case .unverified(let reason) = result { failure = reason }
                    }
                } catch {
                    for record in records { results[record.id] = .unverified(reason: error.localizedDescription) }
                }
                let completed = results
                RunLoop.main.perform { [self] in
                    busy = false; refreshCancellation = nil
                    guard !cancelled else { return }
                    checks.merge(completed) { _, new in new }; checkedAt = Date()
                    do {
                        var next = try CodexClusterCatalog.load(from: index)
                        for i in next.conversations.indices {
                            let record = next.conversations[i]
                            guard record.clusterID == clusterID else { continue }
                            if case .available(let name) = completed[record.id], let name, !name.isEmpty {
                                next.conversations[i].title = name
                            }
                        }
                        try next.save(to: index); catalog = next
                        message = "刷新完成；状态仅代表本次检查，不会自动删除记录。"
                    } catch { message = error.localizedDescription }
                }
            }
        } catch {
            for record in records { checks[record.id] = .unverified(reason: error.localizedDescription) }
            message = error.localizedDescription
        }
    }
    func conversations(in cluster: UUID?) -> [CodexClusterConversation] {
        catalog.conversations.filter { $0.clusterID == cluster }.sorted { $0.lastOpened > $1.lastOpened }
    }
    func prepare(clusterID: UUID, conversationID: String?, title: String, serverID: UUID?,
                 bridge: CodexBridge, completion: @escaping (CodexConversationLaunch) -> Void) {
        guard !busy, !loadFailed, !cancelled, let cluster = catalog.clusters.first(where: { $0.id == clusterID }) else { return }
        do {
            let existing = conversationID.flatMap { id in catalog.conversations.first { $0.id == id && $0.clusterID == clusterID } }
            guard conversationID == nil || existing != nil else { throw ConfigurationError.invalid("请选择所选集群中的对话。") }
            guard existing != nil || catalog.conversations.count < 10000 else { throw ConfigurationError.invalid("集群对话数量已达上限。") }
            let name = try existing?.title ?? catalog.uniqueTitle(title, cluster: clusterID)
            let directory = catalog.directoryURL(for: cluster, defaultDirectory: defaultDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let executable = try bridge.executable()
            var environment = try bridge.saveConnection()
            let relay = try bridge.socksRelay()
            if let relay { environment = try relay.environment(base: environment) }
            busy = true; message = "正在准备集群对话…"
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result: Result<(String, String), Error>
                do {
                    let client = try CodexThreadClient(executable: executable, environment: environment)
                    defer { client.close(); withExtendedLifetime(relay) {} }
                    if let existing {
                        let savedName = try client.read(existing.id, directory: directory.path)
                        result = .success((existing.id, savedName ?? name))
                    } else {
                        result = .success((try client.create(directory: directory.path, name: name), name))
                    }
                } catch { result = .failure(error) }
                RunLoop.main.perform { [self] in
                    busy = false
                    do {
                        let (id, savedName) = try result.get()
                        var next = catalog
                        next.conversations.removeAll { $0.id == id }
                        next.conversations.append(CodexClusterConversation(id: id, clusterID: clusterID, title: savedName, lastOpened: Date()))
                        if let serverID { next.serverClusters[serverID.uuidString] = clusterID }
                        try next.save(to: index); catalog = next; message = ""
                        guard !cancelled else { return }
                        completion(CodexConversationLaunch(threadID: id, directory: directory.path,
                            label: "Codex · " + cluster.name + " · " + savedName, isNew: existing == nil))
                    } catch { message = error.localizedDescription }
                }
            }
        } catch { message = error.localizedDescription }
    }
}
