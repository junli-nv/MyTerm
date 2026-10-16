import AppKit
import SwiftUI
import MyTermCore

final class CodexExecutionRecord: Identifiable {
    let id = UUID(), sessionID: UUID, label: String, command: String
    let associationID: UUID
    let created = Date()
    var reason = ""
    var deliveredOffset = 0
    var authorization = UUID()
    var state = "awaiting_approval"
    var process: CodexCommandProcess?
    var error = ""
    init(sessionID: UUID, label: String, command: String, associationID: UUID? = nil) {
        self.associationID = associationID ?? sessionID
        self.sessionID = sessionID; self.label = label; self.command = command
    }
    func snapshot(offset: Int = 0) throws -> [String: Any] {
        var value = try process?.snapshot(offset: offset) ?? ["state": state, "output": error, "next_offset": 0, "total_bytes": 0]
        value["job_id"] = id.uuidString; value["session_id"] = sessionID.uuidString
        value["command"] = command
        value["reason"] = reason
        return value
    }
}

/// Keep controls reachable in narrow windows and split panes without wrapping buttons.
struct CodexExecutionBar: View {
    @ObservedObject var bridge: CodexBridge
    let sessionID: UUID
    var codexTabID: UUID? = nil
    var body: some View {
        ScrollView(.horizontal) {
            CodexInlineExecutionView(bridge: bridge, sessionID: sessionID, codexTabID: codexTabID)
                .containerRelativeFrame(.horizontal) { width, _ in max(760, width) }
        }.fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// App-owned approval buttons stay beside the Codex TUI. Never inject bytes into
/// the terminal buffer or interpret remote/TUI text as an approval gesture.
struct CodexInlineExecutionView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @ObservedObject var bridge: CodexBridge
    let sessionID: UUID
    var codexTabID: UUID? = nil
    @StateObject private var editor = CodexExecutionEditor()
    private var executionID: UUID { bridge.executionID(for: sessionID, tab: codexTabID) }
    private var records: [CodexExecutionRecord] { bridge.executionRecords.filter { $0.associationID == executionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L10n.text("SSH 执行")).fontWeight(.semibold).fixedSize()
                Spacer(minLength: 0)
                if let deadline = bridge.executionGrants[executionID] {
                    Text(deadline.formatted(date: .omitted, time: .standard)).monospacedDigit()
                        .help(L10n.text("执行授权有效至：") + deadline.formatted(date: .omitted, time: .standard))
                } else { Text(L10n.text(bridge.executionIsExpired(executionID) ? "授权已到期" : "只读")).foregroundStyle(.secondary).fixedSize() }
                Text("\(bridge.remainingExecutionCommands(executionID))/\(bridge.limitsForExecution(executionID).commands)").monospacedDigit().help(L10n.text("剩余命令额度"))
                Button(L10n.text("继续授权")) { bridge.renewExecution(executionID, owner: codexTabID) }
                    .disabled(!bridge.enabled).help("\(bridge.limitsForExecution(executionID).minutes) min / \(bridge.limitsForExecution(executionID).commands)").fixedSize()
                CodexExecutionApprovalMode(bridge: bridge, associationID: executionID).frame(width: 340)
                Spacer(minLength: 0)
                Button {
                    editor.limits = bridge.limitsForExecution(executionID); editor.presented = true
                } label: { Image(systemName: "slider.horizontal.3") }
                    .help(L10n.text("执行设置"))
            }
            if bridge.executionGrants[executionID] != nil && bridge.remainingExecutionCommands(executionID) == 0 {
                Text(L10n.text("命令额度已用尽，请点击继续授权。")).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !bridge.executionAccessMessage(executionID).isEmpty {
                Text(L10n.text(bridge.executionAccessMessage(executionID))).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let pending = records.last(where: { $0.state == "awaiting_approval" }) {
                HStack(spacing: 8) {
                    Label(L10n.text("命令待确认"), systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).fixedSize()
                    Spacer(minLength: 0)
                    Button(L10n.text("单次允许")) { bridge.approveExecution(pending) }.help(L10n.text("允许执行此命令")).fixedSize()
                    Button(L10n.text("始终允许")) { bridge.setAlwaysAllowExecution(executionID, enabled: true) }.help(L10n.text("本会话始终允许")).fixedSize()
                    Button(L10n.text("拒绝")) { bridge.cancelExecution(pending) }.fixedSize()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.label).fontWeight(.semibold)
                        if !pending.reason.isEmpty { Text(pending.reason).fixedSize(horizontal: false, vertical: true) }
                        Text(pending.command).font(.callout.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.visible).frame(height: 80)
            } else if records.contains(where: { $0.state == "queued" }) {
                Text(L10n.text("命令已获准，等待同一 SSH 会话中的其他命令结束。")).foregroundStyle(.secondary)
            }
            if let active = records.first(where: { ["running", "queued"].contains($0.process?.progress.state ?? $0.state) }) {
                HStack {
                    Text(L10n.text("命令执行中"))
                    Spacer()
                    Button(L10n.text("取消当前命令")) { bridge.cancelExecution(active) }
                }
            }
        }.font(.caption).controlSize(.small).padding(6).background(Color(nsColor: .controlBackgroundColor))
            .environment(\.locale, language.locale)
            .sheet(isPresented: $editor.presented) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("执行设置")).font(.headline)
                    CodexExecutionSettings(limits: $editor.limits)
                    Text(L10n.text("应用会取消当前命令并重置授权额度。"))
                    HStack {
                        Button(L10n.text("取消")) { editor.presented = false }
                        Spacer()
                        Button(L10n.text("应用并继续授权")) {
                            bridge.renewExecution(executionID, owner: codexTabID, limits: editor.limits)
                            editor.presented = false
                        }.disabled((try? editor.limits.validate()) == nil)
                    }
                }.padding(20).frame(width: 520)
            }
    }
}

struct CodexExecutionApprovalMode: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @ObservedObject var bridge: CodexBridge
    let associationID: UUID
    var body: some View {
        Picker(L10n.text("命令审批"), selection: Binding(get: { bridge.alwaysAllowedExecution.contains(associationID) }, set: { bridge.setAlwaysAllowExecution(associationID, enabled: $0) })) {
            Text(L10n.text("每条命令确认")).tag(false)
            Text(L10n.text("本会话始终允许")).tag(true)
        }.pickerStyle(.segmented).labelsHidden()
            .disabled(bridge.executionGrants[associationID] == nil)
            .help(L10n.text("仅作用于当前 Codex 标签；切回逐条确认不会中断已经开始的命令。继续授权沿用当前选择。"))
    }
}

final class CodexExecutionEditor: ObservableObject {
    @Published var presented = false
    @Published var limits = CodexExecutionLimits()
}
