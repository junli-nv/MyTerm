import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MyTermCore
import CryptoKit

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
    private let repository: HistoryRepository
    private let queue = DispatchQueue(label: "MyTerm.History", qos: .utility)
    private var lastDigest: [UUID: SHA256.Digest] = [:] // Accessed only on the serial queue.
    private var excluded = Set<UUID>()
    init(directory: URL) { repository = HistoryRepository(directory: directory) }

    func save(_ records: [SessionHistory], wait: Bool = false) {
        let allowed = records.filter { !excluded.contains($0.id) }
        let work = { [self] in
            for record in allowed {
                let digest = SHA256.hash(data: Data(record.text.utf8))
                guard lastDigest[record.id] != digest else { continue }
                do { try repository.save(record); lastDigest[record.id] = digest }
                catch { DispatchQueue.main.async { self.error = "保存会话历史失败：\(error.localizedDescription)" } }
            }
            // Only active records need a cache; archives remain on disk.
            if lastDigest.count > 100 { lastDigest.removeAll() }
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
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
        excluded.insert(id) // An open session must not immediately recreate a deleted archive.
        queue.async { [self] in
            do {
                try repository.delete(id); lastDigest[id] = nil
                DispatchQueue.main.async { self.refresh() }
            } catch { DispatchQueue.main.async { self.excluded.remove(id); self.error = error.localizedDescription } }
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
                Text("保留最近 50,000 行回滚与当前屏幕；每 30 秒及关闭时保存。文本内可用 ⌘F 查找。")
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
