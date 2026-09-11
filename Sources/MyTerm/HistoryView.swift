import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MyTermCore
import CryptoKit
import Combine

struct HistorySummary: Identifiable {
    let id: UUID
    let label: String
    let started: Date
    let updated: Date
}

final class HistoryModel: ObservableObject {
    @Published var entries: [HistorySummary] = []
    @Published var selectedID: UUID? { didSet { loadSelected() } }
    @Published var text = ""
    @Published var query = ""
    @Published var error: String?
    @Published var loading = false
    private(set) var saving = false // Main thread: at most one periodic snapshot batch.
    private let repository: HistoryRepository
    private let queue = DispatchQueue(label: "MyTerm.History", qos: .utility)
    private var lastDigest: [UUID: SHA256.Digest] = [:] // Accessed only on the serial queue.
    private var excluded = Set<UUID>() // Serial queue only.
    private var known = Set<UUID>()
    private var policy = HistoryPolicy()
    private let permissionLock = NSLock()
    private var globalEnabled = false
    private var validPolicy = true
    private var overrides: [UUID: HistoryLoggingMode] = [:]
    func setLoggingMode(_ mode: HistoryLoggingMode, for id: UUID) {
        permissionLock.lock()
        let changed = overrides[id] != mode
        overrides[id] = mode
        permissionLock.unlock()
        if changed { queue.async { self.lastDigest[id] = nil } }
    }
    private func mayWrite(_ id: UUID) -> Bool {
        permissionLock.lock(); defer { permissionLock.unlock() }
        return validPolicy && (overrides[id] ?? .inherit).resolves(global: globalEnabled)
    }
    private var policySubscription: AnyCancellable?
    init(directory: URL) {
        repository = HistoryRepository(directory: directory)
        policySubscription = HistoryPreferences.shared.$policy.sink { [weak self] value in
            guard let self else { return }
            self.permissionLock.lock()
            self.globalEnabled = value.enabled
            self.validPolicy = (try? value.validate()) != nil
            self.permissionLock.unlock()
            self.queue.async {
                if !value.enabled { self.policy.enabled = false }
                guard (try? value.validate()) != nil else { return }
                self.policy = value; self.lastDigest.removeAll()
            }
        }
    }

    func save(_ records: [SessionHistory], wait: Bool = false) {
        guard wait || !saving else { return }
        saving = true
        let work = { [self] in
            defer { if !wait { DispatchQueue.main.async { self.saving = false } } }
            known.formUnion(records.map(\.id))
            for record in records where !excluded.contains(record.id) && mayWrite(record.id) {
                let digest = SHA256.hash(data: Data(record.text.utf8))
                guard lastDigest[record.id] != digest else { continue }
                var effective = policy; effective.enabled = true
                do { try repository.save(record, policy: effective, shouldWrite: { self.mayWrite(record.id) }); lastDigest[record.id] = digest }
                catch { DispatchQueue.main.async { self.error = "保存会话历史失败：\(error.localizedDescription)" } }
            }
            do { if records.contains(where: { mayWrite($0.id) }) { try repository.enforceCapacity(policy) } }
            catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
            // Only active records need a cache; archives remain on disk.
            if lastDigest.count > 100 { lastDigest.removeAll() }
        }
        if wait { queue.sync(execute: work); saving = false } else { queue.async(execute: work) }
    }
    func refresh(select id: UUID? = nil) {
        loading = true
        queue.async { [self] in
            do {
                var summaries: [HistorySummary] = []
                var failures = 0
                for id in try repository.ids() {
                    do {
                        let record = try repository.load(id)
                        summaries.append(HistorySummary(id: id, label: record.label, started: record.started, updated: record.updated))
                    } catch { failures += 1 }
                }
                let sorted = summaries.sorted { $0.updated > $1.updated }
                DispatchQueue.main.async {
                    self.entries = sorted; self.loading = false
                    self.selectedID = id.flatMap { wanted in sorted.contains(where: { $0.id == wanted }) ? wanted : nil }
                        ?? self.selectedID.flatMap { current in sorted.contains(where: { $0.id == current }) ? current : nil }
                        ?? sorted.first?.id
                    if failures > 0 { self.error = "\(failures) 条历史记录无法读取，原文件已保留。" }
                }
            } catch { DispatchQueue.main.async { self.loading = false; self.error = error.localizedDescription } }
        }
    }
    private func loadSelected() {
        text = ""
        guard let id = selectedID else { return }
        queue.async { [self] in
            do {
                let record = try repository.load(id)
                DispatchQueue.main.async { if self.selectedID == id { self.text = record.text } }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func deleteSelected() {
        guard let id = selectedID else { return }
        queue.async { [self] in
            excluded.insert(id) // Do not recreate an explicitly deleted open session.
            do {
                try repository.delete(id); lastDigest[id] = nil
                DispatchQueue.main.async { self.refresh() }
            } catch { excluded.remove(id); DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func cleanHistory(olderOnly: Bool) {
        let alert = NSAlert()
        alert.messageText = L10n.text(olderOnly ? "清理 30 天前的记录？" : "清空全部历史记录？")
        alert.informativeText = L10n.text("删除后无法恢复，不影响服务器配置。已清理的当前会话在重新打开标签页前不会再次保存。")
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: L10n.text("删除记录"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let cutoff = olderOnly ? Date().addingTimeInterval(-30 * 86400) : nil
        queue.async { [self] in
            do {
                let deleted = try repository.clean(before: cutoff)
                excluded.formUnion(deleted)
                if !olderOnly { excluded.formUnion(known) }
                lastDigest.removeAll()
                DispatchQueue.main.async { self.refresh() }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func exportSelected() {
        guard let id = selectedID, let entry = entries.first(where: { $0.id == id }) else { return }
        export(text: text, label: entry.label)
    }
    func export(text: String, label: String) {
        let panel = NSSavePanel(); panel.title = L10n.text("导出会话历史")
        panel.allowedContentTypes = [.plainText]
        let safe = label.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "_")
        panel.nameFieldStringValue = "\(safe)-\(Date().formatted(.iso8601.year().month().day())).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        queue.async { [self] in
            do { try HistoryRepository.export(text, to: url) }
            catch { DispatchQueue.main.async { self.error = "导出失败：\(error.localizedDescription)" } }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var model: HistoryModel
    let refresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("会话历史").font(.title2.bold())
                Spacer()
                Button("刷新", action: refresh).disabled(model.loading)
                Button("导出文本…", action: model.exportSelected).disabled(model.selectedID == nil || model.text.isEmpty)
                Button("删除记录", role: .destructive, action: model.deleteSelected).disabled(model.selectedID == nil)
                Menu("清理历史") {
                    Button("清理 30 天前的记录") { model.cleanHistory(olderOnly: true) }
                    Button("清空全部历史记录", role: .destructive) { model.cleanHistory(olderOnly: false) }
                }
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HSplitView {
                VStack {
                    TextField("搜索会话名称", text: $model.query)
                    List(selection: $model.selectedID) {
                        ForEach(model.entries.filter { model.query.isEmpty || $0.label.localizedCaseInsensitiveContains(model.query) }) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label).lineLimit(1)
                                Text(item.started.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }.tag(item.id)
                        }
                    }
                }.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                HistoryTextView(text: model.text).frame(minWidth: 420)
            }
            HStack {
                Text("自动保存默认关闭，可在设置 → 终端行为中开启并调整限制。文本内可用 ⌘F 查找。")
                Spacer()
                Text("\(model.entries.count) 条记录")
            }.font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
        }.padding(20).frame(width: 960, height: 640)
    }
}

struct HistoryTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false; view.isSelectable = true
        view.isRichText = false; view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = NSSize(width: 10, height: 10)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text; view.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
