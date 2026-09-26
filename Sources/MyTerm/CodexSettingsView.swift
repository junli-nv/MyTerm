import AppKit
import SwiftUI

final class CodexSettingsController {
    private var window: NSWindow?
    func present(workspace: Workspace) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 660, height: 500)
            window.contentView = NSHostingView(rootView: CodexSettingsView(workspace: workspace, bridge: workspace.codex, onStarted: { [weak self] in self?.window?.close() }))
            window.center(); self.window = window
        }
        window?.title = L10n.text("Codex 接入")
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

final class CodexSettingsNavigation: ObservableObject {
    @Published var page = 0
}

struct CodexSettingsView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @ObservedObject var language = LanguagePreferences.shared
    var onStarted: () -> Void
    @StateObject private var chooser = CodexChooserState()
    @StateObject private var navigation: CodexSettingsNavigation
    init(workspace: Workspace, bridge: CodexBridge, onStarted: @escaping () -> Void = {}, navigation: CodexSettingsNavigation = CodexSettingsNavigation()) {
        self.workspace = workspace; self.bridge = bridge; self.onStarted = onStarted
        _navigation = StateObject(wrappedValue: navigation)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSH 会话接入 Codex").font(.title2.bold())
            Picker("配置分类", selection: $navigation.page) {
                Text("Codex 配置").tag(0)
                Text("SSH 会话接入").tag(1)
            }.pickerStyle(.segmented).accessibilityIdentifier("codex-settings-sections")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if navigation.page == 0 { codexConfiguration.disabled(bridge.busy) } else { sshConfiguration }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }.scrollIndicators(.visible)
            if !bridge.message.isEmpty {
                Text(L10n.text(bridge.message)).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).sheet(isPresented: $chooser.presented) {
            CodexSessionChooser(workspace: workspace, bridge: bridge)
        }.environment(\.locale, language.locale)
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in onStarted() }
            .onAppear { bridge.refreshRegistration() }
            .onDisappear { bridge.proxyPassword = "" }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in bridge.proxyPassword = "" }
    }
    @ViewBuilder private var codexConfiguration: some View {
                Text("Codex CLI 与代理").font(.headline)
                TextField("Codex 可执行文件路径", text: $bridge.connection.executable)
                Picker("代理方式", selection: $bridge.connection.proxyMode) {
                    Text("继承启动环境").tag(MyTermCore.CodexProxyMode.inherited)
                    Text("HTTP").tag(MyTermCore.CodexProxyMode.http)
                    Text("SOCKS5").tag(MyTermCore.CodexProxyMode.socks5)
                }.pickerStyle(.segmented)
                if bridge.connection.proxyMode != .inherited {
                    TextField("代理地址", text: $bridge.connection.host)
                    TextField("代理端口", text: $bridge.connection.port)
                    TextField("代理用户名（可选）", text: $bridge.connection.username)
                    SecureField("代理密码（留空沿用已保存密码）", text: $bridge.proxyPassword)
                    HStack {
                        Button("测试代理 HTTPS 连接", action: bridge.testProxy)
                        Button("清除代理密码", action: bridge.clearProxyPassword)
                    }.disabled(bridge.busy)
                }
                HStack(alignment: .top) {
                    if bridge.testingProxy { ProgressView().controlSize(.small) }
                    Text("代理测试状态").fontWeight(.semibold)
                    Text(L10n.text(bridge.proxyTestStatus)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("codex-proxy-status")
                Text("代理仅用于 MyTerm 启动的 Codex，与 SSH 代理独立。自定义代理会替换该进程的代理环境变量，不主动回退直连。浏览器或外部 IDE 的代理需单独设置。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存连接设置") {
                        do { _ = try bridge.saveConnection(); bridge.message = "连接设置已保存，下次启动 Codex 生效。" }
                        catch { bridge.message = error.localizedDescription }
                    }
                }.disabled(bridge.busy)
                Divider()
                Text("Codex 账号").font(.headline)
                HStack {
                    Button("登录 Codex") { bridge.launch(login: true) }
                    Button("检查登录状态") { bridge.checkLogin() }
                    Button("重新登录 Codex") { bridge.launch(login: true, checkSavedLogin: false) }
                }.disabled(bridge.busy)
                HStack(alignment: .top) {
                    if bridge.checkingLogin { ProgressView().controlSize(.small) }
                    Text("登录状态").fontWeight(.semibold)
                    Text(L10n.text(bridge.loginStatus)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("codex-login-status")
                Text("登录仅用于 Codex 账号，不开放任何 SSH 会话。登录信息保存在本机；启动分析时会自动检查，未登录则引导登录。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("外部 Codex／IDE（可选）").font(.headline)
                Text("仅外部 Codex 或 IDE 需要注册 MCP；MyTerm 内的 Codex 标签会自动配置。外部客户端只能访问已授权的 SSH 会话。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("配置外部 Codex 的 MyTerm MCP", action: bridge.configureExternal)
                    Button("刷新注册状态", action: bridge.refreshRegistration)
                    if bridge.checkingRegistration { ProgressView().controlSize(.small) }
                }.disabled(bridge.busy || bridge.checkingRegistration)
                Text(L10n.text(bridge.registrationStatus)).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                if !bridge.registrationError.isEmpty {
                    Text("外部 MCP 注册失败：").foregroundStyle(.red)
                    Text(bridge.registrationError).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if !bridge.registrationPath.isEmpty {
                    Text(bridge.registrationPath).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if let checked = bridge.registrationCheckedAt {
                    Text(L10n.text("最近检查：") + checked.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                }
                Text("注册后重启外部 Codex／IDE 生效。需要停止 SSH 访问时，请在“SSH 会话接入”中关闭接入开关。")
                    .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private var sshConfiguration: some View {
        Text("选择已打开的 SSH 会话交给 Codex 分析。不会接入本地 Shell；默认只读，执行需另行授权，审批方式可在会话中调整。")
            .fixedSize(horizontal: false, vertical: true)
                Text("Codex 配置依赖").font(.headline)
                if let issue = bridge.configurationIssue {
                    Text("请先完成 Codex 配置。").foregroundStyle(.orange)
                    Text(L10n.text(issue)).fixedSize(horizontal: false, vertical: true)
                    Button("前往 Codex 配置") { navigation.page = 0 }
                } else {
                    Text("Codex 路径及代理格式有效；启动时会自动检查登录状态。").fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(bridge.loginStatus)).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if bridge.loginAvailable != true {
                        Text("未登录时先完成登录，再自动继续所选 SSH 分析。").font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("配置修改仅用于新启动的 Codex 标签；代理测试用于诊断，不是启动前的必选步骤。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("SSH 会话分析").font(.headline)
                HStack {
                    Button("启动 Codex 标签") { chooser.presented = true }
                        .disabled(bridge.busy || bridge.configurationIssue != nil || !workspace.sessions.contains(where: { $0.server != nil }))
                    Button("执行记录与控制") { bridge.showExecution() }
                }
                Text("启动时选择 SSH 会话、是否回溯已有输出和执行授权。确认后开启接入，成功创建分析标签后关闭本窗口；可再次打开此入口创建其他分析标签。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if !workspace.sessions.contains(where: { $0.server != nil }) { Text("当前没有 SSH 标签。请先打开需要分析的会话。").font(.caption) }
                if !bridge.lastRead.isEmpty { Text(L10n.text("最近读取：") + bridge.lastRead).font(.caption) }
                Divider()
                Text("SSH 接入状态").font(.headline)
                Toggle("允许 Codex 访问已授权的 SSH 会话", isOn: Binding(get: { bridge.enabled }, set: { $0 ? bridge.start() : bridge.stop() }))
                Text("这是所有 Codex 客户端的 SSH 接入总开关，开启不会自动授权会话；关闭会立即撤销全部读取及执行权限。退出应用后默认关闭。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("历史按设定范围分页读取；单页大小不限制总读取量。只能读取终端缓冲区仍保留的内容，达到行数或容量上限时明确提示截断。")
                    .font(.caption).foregroundStyle(.secondary)
    }
}

import MyTermCore


struct CodexSessionChooser: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @Environment(\.dismiss) private var dismiss
    @StateObject private var selection: CodexChooserState
    init(workspace: Workspace, bridge: CodexBridge, selection: CodexChooserState = CodexChooserState()) {
        self.workspace = workspace; self.bridge = bridge
        _selection = StateObject(wrappedValue: selection)
    }
    var body: some View {
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
            Toggle("接入时读取已有输出", isOn: $selection.includeHistory)
            Text("默认关闭：接入后等待你的任务，从后续命令开始分析。需要回溯排查时再开启；不影响执行命令的完整输出读取。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if selection.includeHistory { CodexHistoryLimits(bridge: bridge) }
            Toggle("允许执行 SSH 命令", isOn: $selection.execute)
            if selection.execute {
                HStack {
                    Text("授权时长（分钟）")
                    TextField("1–1440", value: $bridge.launchExecutionMinutes, format: .number).frame(width: 95)
                    Stepper("", value: $bridge.launchExecutionMinutes, in: 1...1440).labelsHidden()
                }
                HStack {
                    Text("每次授权命令额度")
                    TextField("1–10000", value: $bridge.launchExecutionCommands, format: .number).frame(width: 95)
                    Stepper("", value: $bridge.launchExecutionCommands, in: 1...10000).labelsHidden()
                }
                Text("到期或额度用尽后可在当前标签继续授权，重置额度并恢复逐条确认；如需持续允许，请再次选择。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Text("默认只读。授权后默认逐条确认，可在 Codex 标签中切换为本会话始终允许。独立通道不共享当前终端目录或 tmux 状态。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认并启动") {
                    guard bridge.configurationIssue == nil else { bridge.message = bridge.configurationIssue ?? ""; return }
                    if !bridge.enabled { bridge.start() }
                    bridge.launch(sessionID: selection.selected, includeHistory: selection.includeHistory, execute: selection.execute, limits: MyTermCore.CodexExecutionLimits(minutes: bridge.launchExecutionMinutes, commands: bridge.launchExecutionCommands))
                }.keyboardShortcut(.defaultAction)
                    .disabled(bridge.busy || !workspace.sessions.contains(where: { $0.id == selection.selected && $0.server != nil }))
            }
        }.padding(24) }.scrollIndicators(.visible).frame(width: 510, height: 540)
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in dismiss() }
            .onAppear { selection.selected = nil; selection.includeHistory = false; selection.execute = false }
    }
}

final class CodexChooserState: ObservableObject {
    @Published var presented = false
    @Published var selected: UUID?
    @Published var includeHistory = false
    @Published var execute = false
}

struct CodexHistoryLimits: View {
    @ObservedObject var bridge: CodexBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("历史读取行数", selection: $bridge.historyRows) {
                ForEach([500, 1000, 2000, 5000, 10000], id: \.self) { Text(String($0)).tag($0) }
            }
            Picker("历史总容量上限", selection: $bridge.historyBytes) {
                Text("64 KB").tag(65536)
                Text("256 KB").tag(262144)
                Text("1 MB").tag(1048576)
            }
            Text("默认最近 2000 行、最多 256 KB，分页读取。读取范围越大，使用的模型额度越多。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
