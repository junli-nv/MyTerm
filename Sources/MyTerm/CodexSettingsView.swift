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

struct CodexSettingsView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @ObservedObject var language = LanguagePreferences.shared
    var onStarted: () -> Void = {}
    @StateObject private var chooser = CodexChooserState()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SSH 会话接入 Codex").font(.title2.bold())
                Text("选择已打开的 SSH 会话交给 Codex 分析。不会接入本地 Shell；默认只读，执行 SSH 命令需另行授权并逐条批准。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Codex 账号").font(.headline)
                HStack {
                    Button("登录 Codex") { bridge.launch(login: true) }
                    Button("检查登录状态") { bridge.checkLogin() }
                    Button("重新登录 Codex") { bridge.launch(login: true, checkSavedLogin: false) }
                }.disabled(bridge.busy)
                Text("登录仅用于 Codex 账号，不开放任何 SSH 会话。登录信息保存在本机；启动分析时会自动检查，未登录则引导登录。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                if bridge.busy { ProgressView().controlSize(.small) }
                Text(L10n.text(bridge.message)).font(.caption).fixedSize(horizontal: false, vertical: true)
                Text("SSH 会话分析").font(.headline)
                HStack {
                    Button("启动 Codex 标签") { chooser.presented = true }
                        .disabled(bridge.busy || !workspace.sessions.contains(where: { $0.server != nil }))
                    Button("执行记录与控制") { bridge.showExecution() }
                }
                Text("启动时统一选择 SSH 会话、读取范围、持续监控和执行授权。确认后开启接入，成功创建分析标签后关闭本窗口；可再次打开此入口创建其他分析标签。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if !workspace.sessions.contains(where: { $0.server != nil }) { Text("当前没有 SSH 标签。请先打开需要分析的会话。").font(.caption) }
                if !bridge.lastRead.isEmpty { Text(L10n.text("最近读取：") + bridge.lastRead).font(.caption) }
                Divider()
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
                Text("代理仅用于 MyTerm 启动的 Codex，与 SSH 代理独立。自定义代理会替换该进程的代理环境变量，不主动回退直连。浏览器或外部 IDE 的代理需单独设置。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存连接设置") {
                        do { _ = try bridge.saveConnection(); bridge.message = "连接设置已保存，下次启动 Codex 生效。" }
                        catch { bridge.message = error.localizedDescription }
                    }
                }.disabled(bridge.busy)
                Divider()
                Text("SSH 接入状态").font(.headline)
                Toggle("允许 Codex 访问已授权的 SSH 会话", isOn: Binding(get: { bridge.enabled }, set: { $0 ? bridge.start() : bridge.stop() }))
                Text("这是所有 Codex 客户端的 SSH 接入总开关，开启不会自动授权会话；关闭会立即撤销全部读取、监控及执行权限。退出应用后默认关闭。")
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
                Text("此按钮调用 codex mcp add，更新当前用户的 Codex 配置。重启 IDE／Codex 后，可请求读取开放标签；关闭本窗口不停止共享，请使用上方共享开关。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("历史按设定范围分页读取；单页大小不限制总读取量。只能读取终端缓冲区仍保留的内容，达到行数或容量上限时明确提示截断。")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.sheet(isPresented: $chooser.presented) {
            CodexSessionChooser(workspace: workspace, bridge: bridge)
        }.scrollIndicators(.visible).environment(\.locale, language.locale)
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in onStarted() }
            .onAppear { bridge.refreshRegistration() }
            .onDisappear { bridge.proxyPassword = "" }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in bridge.proxyPassword = "" }
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
            Text("启动后自动读取所选会话。确认启动即允许 Codex 读取该标签的输出。")
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
            CodexHistoryLimits(bridge: bridge)
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
                Text("到期或额度用尽后，可在当前 Codex 标签点击继续授权，按本次配置重置额度；每条命令仍需批准。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Text("默认只读。计划直接展示，无需确认；每条 SSH 命令均须明确确认后执行。独立通道不共享当前终端目录或 tmux 状态。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Toggle("持续监控新输出", isOn: $selection.monitor)
            Text("持续监控会使用 Codex 模型额度。在接入设置中可停止监控；关闭共享或 SSH 标签也会停止。Codex 任务结束后需重新启动监控，不能作为无人值守告警服务。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认并启动") {
                    if !bridge.enabled { bridge.start() }
                    bridge.launch(sessionID: selection.selected, monitor: selection.monitor, execute: selection.execute, limits: MyTermCore.CodexExecutionLimits(minutes: bridge.launchExecutionMinutes, commands: bridge.launchExecutionCommands))
                }.keyboardShortcut(.defaultAction)
                    .disabled(bridge.busy || !workspace.sessions.contains(where: { $0.id == selection.selected && $0.server != nil }))
            }
        }.padding(24) }.scrollIndicators(.visible).frame(width: 510, height: 540)
            .onReceive(bridge.$launchGeneration.dropFirst()) { _ in dismiss() }
            .onAppear { selection.selected = nil; selection.monitor = false; selection.execute = false }
    }
}

final class CodexChooserState: ObservableObject {
    @Published var presented = false
    @Published var selected: UUID?
    @Published var monitor = false
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
