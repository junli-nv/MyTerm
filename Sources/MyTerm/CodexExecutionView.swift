import AppKit
import SwiftUI
import MyTermCore

final class CodexExecutionRecord: Identifiable {
    let id = UUID(), sessionID: UUID, label: String, command: String
    let created = Date()
    var isPlan = false
    var planID = ""
    var reason = ""
    var deliveredOffset = 0
    var authorization = UUID()
    var state = "awaiting_approval"
    var process: CodexCommandProcess?
    var error = ""
    init(sessionID: UUID, label: String, command: String) {
        self.sessionID = sessionID; self.label = label; self.command = command
    }
    func snapshot(offset: Int = 0) throws -> [String: Any] {
        var value = try process?.snapshot(offset: offset) ?? ["state": state, "output": error, "next_offset": 0, "total_bytes": 0]
        value["job_id"] = id.uuidString; value["session_id"] = sessionID.uuidString
        value["command"] = command
        value["plan_id"] = isPlan ? id.uuidString : planID
        value["reason"] = reason
        return value
    }
}

struct CodexExecutionView: View {
    @ObservedObject var bridge: CodexBridge
    @ObservedObject var language = LanguagePreferences.shared
    var sessionID: UUID? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Codex SSH 执行控制").font(.title2.bold())
                Text("独立执行通道不共享终端的目录、环境变量或 tmux 状态。授权时长和命令额度在启动 Codex 标签时设置，可在原标签继续授权；单条最多 60 秒，输出最多 1 MB。停止会关闭执行通道，但远端已脱离会话的后台进程可能继续运行。")
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.text(sessionID == nil ? "停止全部执行并撤销授权" : "停止执行并撤销授权")) {
                    if let sessionID { bridge.revokeExecution(sessionID) } else { bridge.revokeAllExecution() }
                }
                ForEach(bridge.executionRecords.filter { sessionID == nil || $0.sessionID == sessionID }.reversed()) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.label).font(.headline)
                        if record.isPlan { Text("执行前计划").font(.headline) }
                        if !record.reason.isEmpty { Text(record.reason).fixedSize(horizontal: false, vertical: true) }
                        Text(record.command).font(.body.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        let result = try? record.snapshot()
                        Text(L10n.text(result?["state"] as? String ?? record.state))
                        if result?["truncated"] as? Bool == true {
                            Text("输出超限，结果不完整；已阻止自动执行下一条命令。").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        }
                        if let exit = result?["exit_code"] as? Int { Text("exit=\(exit)") }
                        if record.state == "awaiting_approval" {
                            HStack {
                                Button(L10n.text(record.isPlan ? "确认此计划" : "允许执行此命令")) { bridge.approveExecution(record) }
                                Button("拒绝") { bridge.cancelExecution(record) }
                            }
                        } else if result?["state"] as? String == "running" {
                            Button("停止") { bridge.cancelExecution(record) }
                        }
                        Text(result?["output"] as? String ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("界面显示输出开头；Codex 可按偏移读取全部保留输出。记录仅保存在内存中。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary).cornerRadius(8)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.visible).environment(\.locale, language.locale)
    }
}


/// App-owned approval buttons stay beside the Codex TUI. Never inject bytes into
/// the terminal buffer or interpret remote/TUI text as an approval gesture.
struct CodexInlineExecutionView: View {
    @ObservedObject var bridge: CodexBridge
    let sessionID: UUID
    var codexTabID: UUID? = nil
    @StateObject private var presentation = CodexInlinePresentation()
    private var records: [CodexExecutionRecord] { bridge.executionRecords.filter { $0.sessionID == sessionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("SSH 执行").fontWeight(.semibold).fixedSize()
                if let deadline = bridge.executionGrants[sessionID] {
                    Text(deadline.formatted(date: .omitted, time: .standard)).monospacedDigit()
                        .help(L10n.text("执行授权有效至：") + deadline.formatted(date: .omitted, time: .standard))
                } else { Text(L10n.text(bridge.executionIsExpired(sessionID) ? "授权已到期" : "只读")).foregroundStyle(.secondary).fixedSize() }
                Text("\(bridge.remainingExecutionCommands(sessionID))/\(bridge.limitsForExecution(sessionID).commands)").monospacedDigit().help(L10n.text("剩余命令额度"))
                Spacer(minLength: 0)
                Button("继续授权") { bridge.renewExecution(sessionID, owner: codexTabID) }
                    .disabled(!bridge.enabled).help("\(bridge.limitsForExecution(sessionID).minutes) min / \(bridge.limitsForExecution(sessionID).commands)").fixedSize()
                Button(presentation.showHistory ? "收起" : "记录") { presentation.showHistory.toggle() }.fixedSize()
                Button("停止") { bridge.revokeExecution(sessionID) }
                    .disabled(bridge.executionGrants[sessionID] == nil).help(L10n.text("停止执行并撤销授权")).fixedSize()
            }
            if bridge.executionGrants[sessionID] != nil && bridge.remainingExecutionCommands(sessionID) == 0 {
                Text("命令额度已用尽，请点击继续授权。").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !bridge.executionAccessMessage.isEmpty {
                Text(L10n.text(bridge.executionAccessMessage)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let pending = records.last(where: { !$0.isPlan && $0.state == "awaiting_approval" }) {
                HStack(spacing: 8) {
                    Label("命令待确认", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).fixedSize()
                    Spacer(minLength: 0)
                    Button("批准") { bridge.approveExecution(pending) }.help(L10n.text("允许执行此命令")).fixedSize()
                    Button("拒绝") { bridge.cancelExecution(pending) }.fixedSize()
                    if records.contains(where: { $0.isPlan && $0.state == "presented" }) {
                        Button("取消计划") { bridge.cancelPlan(sessionID) }.help(L10n.text("取消计划并停止执行")).fixedSize()
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.label).fontWeight(.semibold)
                        if !pending.reason.isEmpty { Text(pending.reason).fixedSize(horizontal: false, vertical: true) }
                        Text(pending.command).font(.callout.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.visible).frame(height: 80)
            } else if let plan = records.last, plan.isPlan && !presentation.showHistory {
                HStack {
                    Text(L10n.text(plan.state == "cancelled" ? "计划已取消" : "执行前计划"))
                    Spacer()
                    Button(presentation.showPlan ? "收起计划" : "展开计划") { presentation.showPlan.toggle() }.fixedSize()
                    if plan.state == "presented" {
                        Button("取消计划") { bridge.cancelPlan(sessionID) }.help(L10n.text("取消计划并停止执行")).fixedSize()
                    }
                }
                if presentation.showPlan {
                ScrollView { Text(plan.command).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollIndicators(.visible).frame(height: 80)
                }
            } else if presentation.showHistory {
                CodexExecutionView(bridge: bridge, sessionID: sessionID).frame(height: 200)
            }
        }.font(.caption).controlSize(.small).padding(6).background(Color(nsColor: .controlBackgroundColor))
    }
}

final class CodexInlinePresentation: ObservableObject {
    @Published var showHistory = false
    @Published var showPlan = true
}
