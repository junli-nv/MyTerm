import AppKit
import SwiftUI
import MyTermCore

/// Launch settings live here; the action row stays outside the scrolling form.
struct CodexSessionChooser: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @Environment(\.dismiss) private var dismiss
    @StateObject private var clusters: CodexClusterModel
    @StateObject private var selection: CodexChooserState
    init(workspace: Workspace, bridge: CodexBridge, selection: CodexChooserState = CodexChooserState()) {
        self.workspace = workspace; self.bridge = bridge
        _selection = StateObject(wrappedValue: selection)
        _clusters = StateObject(wrappedValue: CodexClusterModel(root: workspace.credentialStore.directory.deletingLastPathComponent()))
    }
    var body: some View {
        VStack(spacing: 0) {
            form.disabled(clusters.busy || bridge.busy)
            Divider()
            actions
        }.frame(minWidth: 640, idealWidth: 720, maxWidth: .infinity, minHeight: 480, idealHeight: 680, maxHeight: .infinity)
            .environment(\.locale, language.locale)
            .onDisappear { clusters.cancelLaunch() }
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in dismiss() }
            .onAppear {
                selection.selected = nil; selection.includeHistory = false; selection.execute = true
                selection.conversationTitle = L10n.text("日常运维")
                if selection.clusterID == nil {
                    selection.clusterID = clusters.add("Default")
                    selection.conversationID = nil; selection.resume = false
                }
            }
            .onChange(of: selection.selected) { _, id in
                guard let session = workspace.sessions.first(where: { $0.id == id }), let server = session.sourceServer else { return }
                if let saved = clusters.catalog.serverClusters[server.id.uuidString] { selectCluster(saved) }
                else if selection.clusterID == nil { selection.clusterName = workspace.groups.first(where: { $0.serverIDs.contains(server.id) })?.name ?? "" }
            }
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
            clusterForm
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

    private func selectCluster(_ id: UUID?) {
        selection.clusterID = id
        selection.conversationID = clusters.conversations(in: id).first?.id
        selection.resume = selection.conversationID != nil
    }
    private var clusterForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("集群与对话").font(.headline)
            Toggle("从全部 Codex 历史中恢复（旧版入口）", isOn: $selection.legacyPicker)
            if selection.legacyPicker {
                Text("在 Codex 原生列表中选择旧对话；重新关联本次 SSH，不自动归入集群。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("集群", selection: Binding(get: { selection.clusterID }, set: { selectCluster($0) })) {
                    if !clusters.catalog.clusters.contains(where: { $0.name == "Default" }) {
                        Text("默认项目").tag(Optional<UUID>.none)
                    }
                    ForEach(clusters.catalog.clusters) { cluster in Text(cluster.name == "Default" ? L10n.text("默认项目") : cluster.name).tag(Optional(cluster.id)) }
                }
                HStack {
                    TextField("新集群名称", text: $selection.clusterName)
                    Button("创建集群") { if let id = clusters.add(selection.clusterName) { selectCluster(id); selection.clusterName = "" } }
                        .disabled(selection.clusterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clusters.busy)
                }
                Toggle("继续已有集群对话", isOn: $selection.resume)
                if selection.resume {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(clusters.conversations(in: selection.clusterID)) { conversation in
                                Button { selection.conversationID = conversation.id } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: selection.conversationID == conversation.id ? "largecircle.fill.circle" : "circle")
                                        Text(conversation.title).fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        Text(conversation.lastOpened, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if clusters.conversations(in: selection.clusterID).isEmpty { Text("该集群还没有对话，请新建对话。") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160).scrollIndicators(.visible)
                } else {
                    TextField("对话名称（默认日常运维）", text: $selection.conversationTitle)
                }
                CodexClusterManagement(clusters: clusters, workspace: workspace, selection: selection)
                Text("集群是稳定的项目分类，SSH 只是连接入口。继续对话保留名称与历史；新建同名对话才追加日期和时分秒。恢复后请先确认当前目标。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !clusters.message.isEmpty { Text(L10n.text(clusters.message)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if !bridge.message.isEmpty { Text(L10n.text(bridge.message)).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }.disabled(clusters.busy)
    }

    private var actions: some View {
        CodexLaunchActions(
            enabled: !bridge.busy && !clusters.busy && (selection.legacyPicker || (!selection.resume || selection.conversationID != nil)) && (!selection.execute || (try? bridge.launchExecutionSettings.validate()) != nil)
                && workspace.sessions.contains(where: { $0.id == selection.selected && $0.server != nil }),
            cancel: { clusters.cancelLaunch(); dismiss() },
            launch: {
                guard bridge.configurationIssue == nil else { bridge.message = bridge.configurationIssue ?? ""; return }
                if !bridge.enabled { bridge.start() }
                if selection.legacyPicker {
                    bridge.launch(sessionID: selection.selected, includeHistory: selection.includeHistory,
                        execute: selection.execute, limits: bridge.launchExecutionSettings, resume: true)
                } else if let clusterID = selection.clusterID ?? clusters.add("Default") {
                    let target = selection.selected
                    let includeHistory = selection.includeHistory, execute = selection.execute
                    let limits = bridge.launchExecutionSettings
                    let existing = selection.resume ? selection.conversationID : nil
                    let title = selection.conversationTitle.isEmpty ? L10n.text("日常运维") : selection.conversationTitle
                    let serverID = workspace.sessions.first(where: { $0.id == target })?.sourceServer?.id
                    bridge.checkLogin(loginIfNeeded: true, shouldContinue: { !clusters.cancelled }) {
                        clusters.prepare(clusterID: clusterID, conversationID: existing, title: title, serverID: serverID, bridge: bridge) { conversation in
                            bridge.launch(sessionID: target, includeHistory: includeHistory, execute: execute,
                                limits: limits, checkSavedLogin: false, resume: true, conversation: conversation)
                        }
                    }
                }
            }
        ).frame(height: 28).padding(.horizontal, 24).padding(.vertical, 16)
    }
}
