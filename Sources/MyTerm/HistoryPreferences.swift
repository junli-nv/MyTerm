import AppKit
import SwiftUI
import MyTermCore

final class HistoryPreferences: ObservableObject {
    static let shared = HistoryPreferences()
    static func validMemoryBudget(_ value: Int) -> Bool { value == 0 || (16...16384).contains(value) }
    @Published var memoryBudgetMiB: Int = 256 {
        didSet {
            guard Self.validMemoryBudget(memoryBudgetMiB),
                  !ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
            UserDefaults.standard.set(memoryBudgetMiB, forKey: "terminal.historyMemoryMiB")
        }
    }
    @Published var policy: HistoryPolicy {
        didSet {
            guard !ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
            var saved = policy
            if (try? saved.validate()) == nil {
                saved = UserDefaults.standard.data(forKey: "terminal.history")
                    .flatMap { try? JSONDecoder().decode(HistoryPolicy.self, from: $0) } ?? HistoryPolicy()
                // A disable action must persist even while a numeric field is invalid.
                if !policy.enabled { saved.enabled = false }
            }
            if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "terminal.history") }
        }
    }
    init() {
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test"),
           let stored = UserDefaults.standard.object(forKey: "terminal.historyMemoryMiB") as? Int,
           Self.validMemoryBudget(stored) { memoryBudgetMiB = stored }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test"),
           let data = UserDefaults.standard.data(forKey: "terminal.history"),
           let value = try? JSONDecoder().decode(HistoryPolicy.self, from: data), (try? value.validate()) != nil {
            policy = value
        } else { policy = HistoryPolicy() }
    }
}

final class HistorySettingsDraft: ObservableObject {
    @Published var policy = HistoryPreferences.shared.policy
    @Published var memoryBudgetMiB = HistoryPreferences.shared.memoryBudgetMiB
}

struct HistorySettingsView: View {
    @StateObject private var draft = HistorySettingsDraft()
    @ObservedObject var preferences = HistoryPreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会话日志与历史").font(.headline)
            Toggle("全局默认：自动保存会话日志", isOn: $preferences.policy.enabled)
            Text("默认关闭。会话可选择跟随全局、始终保存或不保存。全局开关仅影响跟随全局的会话，已有历史保留，手动导出始终可用。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("使用 gzip 快速压缩（推荐）", isOn: $preferences.policy.compressed)
            ThemeSettingRow(title: "单会话最大行数") {
                TextField("100–1,000,000", value: $draft.policy.maximumLines, format: .number.grouping(.never))
            }
            ThemeSettingRow(title: "历史内存预算（MiB）") {
                TextField("0 / 16–16,384", value: $draft.memoryBudgetMiB, format: .number.grouping(.never))
            }
            Text("默认 256 MiB，在所有终端标签间均分；0 表示仅限制行数。按字符行内存估算，不是应用总内存上限，不含当前屏幕、图片和界面。预算不足时丢弃最旧回看内容；新建标签、加宽窗口或降低预算可能触发清理，不影响已有磁盘日志。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !HistoryPreferences.validMemoryBudget(draft.memoryBudgetMiB) {
                Text("历史内存预算须为 0 或 16–16,384 MiB。")
                    .font(.caption).foregroundStyle(.red)
            }
            ThemeSettingRow(title: "单文件上限（MiB）") {
                TextField("1–1,024", value: $draft.policy.fileMiB, format: .number.grouping(.never))
            }
            ThemeSettingRow(title: "日志总容量（MiB）") {
                TextField("1–102,400", value: $draft.policy.totalMiB, format: .number.grouping(.never))
            }
            if (try? draft.policy.validate()) == nil {
                Text("历史限制无效：行数 100–1,000,000，单文件 1–1,024 MiB，总容量 1–102,400 MiB，且总容量不能小于单文件。")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Button("应用日志限制") {
                var value = draft.policy
                value.enabled = preferences.policy.enabled; value.compressed = preferences.policy.compressed
                preferences.policy = value
                preferences.memoryBudgetMiB = draft.memoryBudgetMiB
            }.disabled((try? draft.policy.validate()) == nil || !HistoryPreferences.validMemoryBudget(draft.memoryBudgetMiB))
            Text("点击应用后调整限制。文件与总容量按压缩后大小计算；超限保留最新内容或清理最久未更新的记录。旧记录可在历史窗口清理。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
