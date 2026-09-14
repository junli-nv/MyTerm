import AppKit
import SwiftUI

final class CodexSettingsController {
    private var window: NSWindow?
    func present(workspace: Workspace) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 660, height: 500)
            window.contentView = NSHostingView(rootView: CodexSettingsView(workspace: workspace, bridge: workspace.codex))
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
    @StateObject private var chooser = CodexChooserState()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Codex 接入").font(.title2.bold())
                Text("按需读取已开放的 SSH 标签，无需保存日志。内容会交给 Codex 分析；此接口只读，不提供执行远端命令、密码或密钥访问。")
                Toggle("开启本机 Codex 只读共享", isOn: Binding(get: { bridge.enabled }, set: { $0 ? bridge.start() : bridge.stop() }))
                Text("每次启动默认关闭。只共享勾选的标签，关闭共享或标签后立即撤销；已发送给 Codex 的内容无法撤回。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(workspace.sessions.filter { $0.server != nil }) { session in
                    CodexSessionPermission(session: session, bridge: bridge)
                }
                if !workspace.sessions.contains(where: { $0.server != nil }) { Text("当前没有 SSH 标签。请先打开需要分析的会话。") }
                if !bridge.lastRead.isEmpty { Text(L10n.text("最近读取：") + bridge.lastRead).font(.caption) }
                CodexHistoryLimits(bridge: bridge)
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
                    Button("登录 Codex") { bridge.launch(login: true) }.disabled(!bridge.enabled)
                    Button("启动 Codex 标签") { chooser.presented = true }.disabled(!bridge.enabled)
                }.disabled(bridge.busy)
                HStack {
                    Button("检查登录状态") { bridge.checkLogin() }
                    Button("重新登录 Codex") { bridge.launch(login: true, checkSavedLogin: false) }.disabled(!bridge.enabled)
                }.disabled(bridge.busy)
                Text("登录信息由 Codex 保存在本机，重启或升级 MyTerm 后可继续使用。已登录时直接启动标签即可；此处检查本地凭据，不验证服务端是否已撤销登录。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
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
                if bridge.busy { ProgressView().controlSize(.small) }
                Text(L10n.text(bridge.message)).font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.sheet(isPresented: $chooser.presented) {
            CodexSessionChooser(workspace: workspace, bridge: bridge)
        }.scrollIndicators(.visible).environment(\.locale, language.locale)
            .onAppear { bridge.refreshRegistration() }
            .onDisappear { bridge.proxyPassword = "" }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in bridge.proxyPassword = "" }
    }
}
private struct CodexSessionPermission: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var bridge: CodexBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: Binding(get: { bridge.allowed.contains(session.id) }, set: { value in
            if value { bridge.allowed.insert(session.id) } else { bridge.allowed.remove(session.id) }
        })) {
            Text(session.label).fixedSize(horizontal: false, vertical: true)
        }.disabled(!bridge.enabled)
        if bridge.monitored.contains(session.id) {
            HStack {
                Text("已允许持续监控").font(.caption)
                Button("停止监控") { bridge.stopMonitoring(session.id) }
            }
        }
        }
    }
}
import MyTermCore


struct CodexSessionChooser: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var bridge: CodexBridge
    @Environment(\.dismiss) private var dismiss
    @StateObject private var selection = CodexChooserState()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择 SSH 会话").font(.title2.bold())
            Text("启动后自动读取所选会话。确认启动即允许 Codex 读取该标签的输出。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workspace.sessions.filter { $0.server != nil }) { session in
                        Button { selection.selected = session.id } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selection.selected == session.id ? "largecircle.fill.circle" : "circle")
                                Text(session.label).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if !workspace.sessions.contains(where: { $0.server != nil }) {
                        Text("当前没有 SSH 标签。请先打开需要分析的会话。")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.visible)
            CodexHistoryLimits(bridge: bridge)
            Toggle("持续监控新输出", isOn: $selection.monitor)
            Text("持续监控会使用 Codex 模型额度。在接入设置中可停止监控；关闭共享或 SSH 标签也会停止。Codex 任务结束后需重新启动监控，不能作为无人值守告警服务。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认并启动") {
                    bridge.launch(sessionID: selection.selected, monitor: selection.monitor)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(!bridge.enabled || !workspace.sessions.contains(where: { $0.id == selection.selected && $0.server != nil }))
            }
        }.padding(24).frame(width: 510, height: 510)
            .onAppear { selection.selected = nil; selection.monitor = false }
    }
}

final class CodexChooserState: ObservableObject {
    @Published var presented = false
    @Published var selected: UUID?
    @Published var monitor = false
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
