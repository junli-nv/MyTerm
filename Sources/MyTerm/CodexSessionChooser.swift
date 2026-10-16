import AppKit
import SwiftUI
import MyTermCore

/// Launch settings live here; the action row stays outside the scrolling form.
struct CodexSessionChooser: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @Environment(\.dismiss) private var dismiss
    @StateObject private var selection: CodexChooserState
    init(workspace: Workspace, bridge: CodexBridge, selection: CodexChooserState = CodexChooserState()) {
        self.workspace = workspace; self.bridge = bridge
        _selection = StateObject(wrappedValue: selection)
    }
    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            actions
        }.frame(minWidth: 640, idealWidth: 720, maxWidth: .infinity, minHeight: 480, idealHeight: 680, maxHeight: .infinity)
            .environment(\.locale, language.locale)
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in dismiss() }
            .onAppear { selection.selected = nil; selection.includeHistory = false; selection.execute = true }
    }

    private var form: some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            Text("选择 SSH 会话").font(.title2.bold())
            Text("确认启动即允许 Codex 按任务需要读取所选 SSH 标签。默认不回溯已有输出。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workspace.sessions.filter { $0.server != nil }) { session in
                        Button { selection.selected = session.id } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selection.selected == session.id ? "largecircle.fill.circle" : "circle")
                                Text(session.label + " · " + (session.server?.host ?? "")).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if !workspace.sessions.contains(where: { $0.server != nil }) {
                        Text("当前没有 SSH 标签。请先打开需要分析的会话。")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.visible).frame(minHeight: 100, maxHeight: 220)
            Toggle("恢复已有 Codex 对话", isOn: $selection.resume)
            if selection.resume {
                Text("启动后在 Codex 历史列表中选择对话。恢复对话历史，但重新绑定本次选择的 SSH；旧 UUID、授权和命令任务不会复用。恢复后请确认目标，再继续任务。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("接入时读取已有输出", isOn: $selection.includeHistory)
            Text("默认关闭：接入后等待你的任务，从后续命令开始分析。需要回溯排查时再开启；不影响执行命令的完整输出读取。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if selection.includeHistory { CodexHistoryLimits(bridge: bridge) }
            Toggle("允许执行 SSH 命令", isOn: $selection.execute)
            if selection.execute {
                CodexExecutionSettings(limits: $bridge.launchExecutionSettings)
            }
            Text("默认启用命令执行；取消勾选可保持只读。请核对审批模式。独立通道不共享当前终端目录或 tmux 状态。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.padding(24) }.scrollIndicators(.visible)
    }

    private var actions: some View {
        CodexLaunchActions(
            enabled: !bridge.busy && (!selection.execute || (try? bridge.launchExecutionSettings.validate()) != nil)
                && workspace.sessions.contains(where: { $0.id == selection.selected && $0.server != nil }),
            cancel: { dismiss() },
            launch: {
                guard bridge.configurationIssue == nil else { bridge.message = bridge.configurationIssue ?? ""; return }
                if !bridge.enabled { bridge.start() }
                bridge.launch(sessionID: selection.selected, includeHistory: selection.includeHistory,
                              execute: selection.execute, limits: bridge.launchExecutionSettings, resume: selection.resume)
            }
        ).frame(height: 28).padding(.horizontal, 24).padding(.vertical, 16)
    }
}
