import SwiftUI
import AppKit
import MyTermCore

@main
struct MyTermApp {
    static func main() {
        if CommandLine.arguments.contains("--smoke-test"),
           let index = CommandLine.arguments.firstIndex(of: "--codex-launch-arguments"),
           CommandLine.arguments.indices.contains(index + 1),
           let args = try? CodexConnection.launchArguments(appExecutable: CommandLine.arguments[index + 1], localDirectory: CommandLine.arguments.contains("--codex-local-work") ? FileManager.default.temporaryDirectory.path : nil, association: CommandLine.arguments.contains("--codex-scoped-check") ? UUID(uuidString: "11111111-2222-3333-4444-555555555555") : nil, resume: CommandLine.arguments.contains("--codex-resume")),
           let data = try? JSONSerialization.data(withJSONObject: args) {
            print(String(decoding: data, as: UTF8.self)); return
        }
        if CommandLine.arguments.contains("--myterm-mcp") { CodexMCP.run(); return }
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["MYTERM_ASKPASS_SOCKET"], let token = environment["MYTERM_ASKPASS_TOKEN"] {
            do {
                guard let answer = try AskpassChannel.answer(path: path, token: token, prompt: CommandLine.arguments.dropFirst().first ?? "SSH authentication", hint: environment["SSH_ASKPASS_PROMPT"]) else { exit(1) }
                FileHandle.standardOutput.write(Data((answer + "\n").utf8)); exit(0)
            } catch { exit(1) }
        }
        if CommandLine.arguments.contains("--smoke-test"),
           let index = CommandLine.arguments.firstIndex(of: "--jump-probe-check"), CommandLine.arguments.indices.contains(index + 1) {
            JumpProbeCheck.run(path: CommandLine.arguments[index + 1]); return
        }
        // AppKit must see this before creating input contexts. Terminal programs
        // need held letters as repeated keys, not the macOS accent picker.
        // This is an application-domain preference; never change NSGlobalDomain.
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspace: Workspace!
    private var window: NSWindow!
    private let codexSettings = CodexSettingsController()
    private let updates = AppUpdateController()
    private let systemMenuLocalizer = SystemMenuLocalizer()
    private var languageObserver: NSObjectProtocol?
    private var shortcutObserver: NSObjectProtocol?
    private var sheetObserver: NSObjectProtocol?
    private var tabKeyMonitor: Any?
    private var checkDirectory: URL?
    let applicationIcon = Bundle.main.url(forResource: "MyTerm", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    deinit {
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        if let tabKeyMonitor { NSEvent.removeMonitor(tabKeyMonitor) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let applicationIcon { NSApp.applicationIconImage = applicationIcon }
        if (ProcessInfo.processInfo.arguments.contains("--window-controls-check") || ProcessInfo.processInfo.arguments.contains("--codex-login-check") || ProcessInfo.processInfo.arguments.contains("--split-check")), ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            let directory = URL(fileURLWithPath: "/tmp/myterm-window-check-\(UUID())")
            checkDirectory = directory
            workspace = Workspace(applicationSupportDirectory: directory)
        } else { workspace = Workspace() }
        if ProcessInfo.processInfo.arguments.contains("--codex-login-check"), ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            CodexBridgeCheck.runLoginLifecycle()
            return
        }
        installMenus()
        shortcutObserver = NotificationCenter.default.addObserver(forName: SplitShortcutPreferences.didChange, object: nil, queue: .main) { [weak self] _ in self?.installMenus() }
        languageObserver = NotificationCenter.default.addObserver(forName: LanguagePreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.installMenus()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "MyTerm"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 850, height: 540)
        window.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: WorkspaceView(workspace: workspace).ignoresSafeArea(.container, edges: .top))
        content.safeAreaRegions = []
        window.contentView = content
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
            // A newly created pane may mount while the chooser is dismissing.
            self?.workspace.focusSelectedPane()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, self.window.attachedSheet == nil else { return event }
            if SplitShortcutDispatch.handle(event, workspace: self.workspace) { return nil }
            guard event.keyCode == 48 else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers == [.control] || modifiers == [.control, .shift] else { return event }
            self.workspace.selectAdjacentTab(modifiers.contains(.shift) ? -1 : 1)
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--split-check"), ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            workspace.newLocal()
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [self] _ in
                do {
                    try SplitPaneCheck.run()
                    try PaneBroadcastCheck.run()
                    try AppUpdateCheck.run()
                    try SplitPaneCheck.shortcuts(window: window, workspace: workspace)
                    workspace.stopAll(); NSApp.terminate(nil)
                } catch { workspace.stopAll(); fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--window-controls-check"),
           ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            workspace.sidebarVisible = false
            workspace.newLocal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                WindowControlsCheck.run(window: window, workspace: workspace)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test"),
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--tmux-check"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                TmuxWindowCheck().run(fixture: ProcessInfo.processInfo.arguments[index + 1]) { result in
                    switch result {
                    case .success: NSApp.terminate(nil)
                    case .failure(let error): fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1)
                    }
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test"),
           ProcessInfo.processInfo.arguments.contains("--transfer-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                ZmodemWindowCheck().run { result in
                    switch result {
                    case .success: NSApp.terminate(nil)
                    case .failure(let error): fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1)
                    }
                }
            }
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                guard workspace.sessions.isEmpty, workspace.selected == nil else {
                    fputs("FAIL: startup unexpectedly created a terminal session\n", stderr); exit(1)
                }
                print("PASS: startup displays the start page without creating a local session")
                workspace.newLocal()
                // Run from the event loop so checks can service asynchronous main-queue drop callbacks.
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [self] _ in AppSmokeCheck.run(workspace) }
            }
        }
        #endif
    }

    private func installMenus() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: L10n.text(title), action: nil, keyEquivalent: "")
            let child = NSMenu(title: L10n.text(title))
            item.submenu = child
            menu.addItem(item)
            return child
        }
        let app = submenu("MyTerm")
        app.addItem(withTitle: L10n.text("关于 MyTerm"), action: #selector(showAbout), keyEquivalent: "").target = self
        app.addItem(withTitle: L10n.text("检查更新…"), action: #selector(checkUpdates), keyEquivalent: "").target = self
        app.addItem(withTitle: L10n.text("Codex 接入…"), action: #selector(showCodexSettings), keyEquivalent: "").target = self
        let settings = app.addItem(withTitle: L10n.text("设置…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        app.addItem(withTitle: L10n.text("退出 MyTerm"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("文件")
        for (title, action, key) in [("新建本地终端", #selector(newTerminal), "t"),
                                    ("添加 SSH 服务器…", #selector(addServer), "n"),
                                    ("关闭当前分屏 / 标签页", #selector(closeTab), "w")] {
            let item = file.addItem(withTitle: L10n.text(title), action: action, keyEquivalent: key)
            item.target = self
        }
        let importItem = file.addItem(withTitle: L10n.text("从 SSH 配置导入…"), action: #selector(importSSH), keyEquivalent: "i")
        importItem.keyEquivalentModifierMask = [.command, .shift]; importItem.target = self
        let saveItem = file.addItem(withTitle: L10n.text("保存当前会话…"), action: #selector(saveSession), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.command, .shift]; saveItem.target = self
        file.addItem(withTitle: L10n.text("导入会话配置…"), action: #selector(importSessions), keyEquivalent: "").target = self
        file.addItem(withTitle: L10n.text("导出会话配置…"), action: #selector(exportSessions), keyEquivalent: "").target = self
        file.addItem(withTitle: L10n.text("SSH 配置检查与导出…"), action: #selector(checkSSHConfiguration), keyEquivalent: "").target = self
        file.addItem(withTitle: L10n.text("导出偏好设置备份…"), action: #selector(exportPreferences), keyEquivalent: "").target = self
        file.addItem(withTitle: L10n.text("恢复偏好设置备份…"), action: #selector(restorePreferences), keyEquivalent: "").target = self
        let historyItem = file.addItem(withTitle: L10n.text("会话历史…"), action: #selector(showHistory), keyEquivalent: "")
        historyItem.keyEquivalentModifierMask = [.command, .shift]; historyItem.target = self
        let exportItem = file.addItem(withTitle: L10n.text("导出当前会话文本…"), action: #selector(exportHistory), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]; exportItem.target = self
        let edit = submenu("编辑")
        edit.addItem(withTitle: L10n.text("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.text("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.text("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.text("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.text("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = edit.addItem(withTitle: L10n.text("查找文本"), action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let windows = submenu("窗口")
        let shortcuts = SplitShortcutPreferences.shared.value
        for (title, action, binding) in [("上下分屏", #selector(splitHorizontally), shortcuts.horizontal),
                                         ("左右分屏", #selector(splitVertically), shortcuts.vertical)] {
            let item = windows.addItem(withTitle: L10n.text(title), action: action, keyEquivalent: binding.key)
            item.keyEquivalentModifierMask = binding.modifiers; item.target = self
        }
        windows.addItem(.separator())
        windows.addItem(withTitle: L10n.text("上下分屏并选择会话…"), action: #selector(chooseHorizontalSplit), keyEquivalent: "").target = self
        windows.addItem(withTitle: L10n.text("左右分屏并选择会话…"), action: #selector(chooseVerticalSplit), keyEquivalent: "").target = self
        let nextTab = windows.addItem(withTitle: L10n.text("下一个会话页"), action: #selector(selectNextTab), keyEquivalent: "\t")
        nextTab.keyEquivalentModifierMask = [.control]; nextTab.target = self
        let previousTab = windows.addItem(withTitle: L10n.text("上一个会话页"), action: #selector(selectPreviousTab), keyEquivalent: "\t")
        previousTab.keyEquivalentModifierMask = [.control, .shift]; previousTab.target = self
        windows.addItem(.separator())
        let sidebar = windows.addItem(withTitle: L10n.text("显示 / 隐藏侧栏"), action: #selector(toggleSidebar), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]; sidebar.target = self
        windows.addItem(withTitle: L10n.text("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: L10n.text("缩放"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        systemMenuLocalizer.attach(edit: edit, window: windows)
        NSApp.windowsMenu = windows
        let help = submenu("帮助")
        help.addItem(withTitle: L10n.text("终端诊断…"), action: #selector(showTerminalDiagnostics), keyEquivalent: "").target = self
        NSApp.mainMenu = menu
    }

    @objc private func showTerminalDiagnostics() { TerminalDiagnostics.shared.present(workspace: workspace) }
    @objc private func showAbout() {
        // Load the bundled artwork directly, avoiding a stale Launch Services icon.
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let applicationIcon { options[.applicationIcon] = applicationIcon }
        let credits = NSMutableAttributedString(string: "Junli Zhang\n", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        credits.append(NSAttributedString(string: "https://github.com/junli-nv/MyTerm", attributes: [
            .link: URL(string: "https://github.com/junli-nv/MyTerm")!,
            .font: NSFont.systemFont(ofSize: 12)
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        options[.credits] = credits
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    @objc private func splitHorizontally() { openSplit(.horizontal) }
    @objc private func splitVertically() { openSplit(.vertical) }
    @objc private func chooseHorizontalSplit() { openSplit(.horizontal, chooseSession: true) }
    @objc private func chooseVerticalSplit() { openSplit(.vertical, chooseSession: true) }
    private func openSplit(_ axis: PaneAxis, chooseSession: Bool = false) {
        guard NSApp.keyWindow === window, window.attachedSheet == nil else { return }
        workspace.requestSplit(axis, chooseSession: chooseSession)
    }
    @objc private func newTerminal() { workspace.newLocal() }
    @objc private func selectNextTab() {
        guard NSApp.keyWindow === window, window.attachedSheet == nil else { return }
        workspace.selectAdjacentTab(1)
    }
    @objc private func selectPreviousTab() {
        guard NSApp.keyWindow === window, window.attachedSheet == nil else { return }
        workspace.selectAdjacentTab(-1)
    }
    @objc private func toggleSidebar() { workspace.sidebarVisible.toggle() }
    @objc private func showHistory() { workspace.showHistory() }
    @objc private func exportHistory() { workspace.exportHistory() }
    @objc private func importSSH() { workspace.importPresented = true }
    @objc private func saveSession() { workspace.saveSession() }
    @objc private func importSessions() { workspace.importSessions() }
    @objc private func exportSessions() { workspace.exportSessions() }
    @objc private func checkSSHConfiguration() { workspace.showSSHConfigurationAudit() }
    @objc private func exportPreferences() { PreferencesBackupController.export(workspace: workspace) }
    @objc private func restorePreferences() { PreferencesBackupController.restore(workspace: workspace) }
    @objc private func checkUpdates() { updates.present() }
    @objc private func showCodexSettings() { codexSettings.present(workspace: workspace) }
    @objc private func showSettings() { MouseSettingsController.shared.present() }
    @objc private func addServer() { workspace.editor = Server() }
    @objc private func closeTab() { if let session = workspace.selected { workspace.close(session) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        workspace?.codex.stop()
        workspace?.saveOnExit(); workspace?.stopAll()
        if let checkDirectory { try? FileManager.default.removeItem(at: checkDirectory) }
    }
}

struct WorkspaceView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var workspace: Workspace
    @ObservedObject var theme = ThemePreferences.shared

    @ViewBuilder private var newSessionActions: some View {
        Button("新建 SSH 会话…") { workspace.editor = Server() }
        Button("新建本地会话") { workspace.newLocal() }
        if !workspace.servers.isEmpty {
            Menu("连接已保存的服务器") {
                ForEach(workspace.servers) { server in
                    Button(server.displayName) { workspace.connect(server) }
                }
            }
        }
        if !workspace.savedSessions.isEmpty {
            Menu("打开已保存会话") {
                ForEach(workspace.savedSessions) { saved in
                    Button("\(saved.name)（\(saved.tabs.count) 个会话）") { workspace.restore(saved) }
                }
            }
        }
        Divider()
        Button("导入会话配置…", action: workspace.importSessions)
    }

    var body: some View {
        VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 78)
                    TabBarButton(symbol: "sidebar.left", tooltip: "显示 / 隐藏侧栏 ⌃⌘S", identifier: "tabbar.sidebar", selected: workspace.sidebarVisible) {
                        workspace.sidebarVisible.toggle()
                    }.frame(width: 28, height: 28).contentShape(Rectangle()).padding(.horizontal, 4)
                    if let session = workspace.selected {
                        TerminalStatusBarButton(session: session)
                    }
                    GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(workspace.visibleTabs) { session in
                                SessionTabControl(workspace: workspace, session: session)
                                    .frame(height: 30).fixedSize(horizontal: true, vertical: false)
                            }
                            Menu { newSessionActions } label: {
                                Text("新建会话…").font(.system(size: 11)).foregroundStyle(.secondary)
                                    .frame(width: 90, height: 26)
                                    .contentShape(Rectangle())
                            }.menuStyle(.borderlessButton)
                                .contextMenu { newSessionActions }
                                .help("点击新建会话或打开已保存会话")
                            TabBarDragArea().frame(minWidth: 40, maxWidth: .infinity, minHeight: 26)
                                .contextMenu { newSessionActions }
                                .help("双击空白处最大化 / 还原窗口，拖动以移动窗口")
                        }.padding(.horizontal, 4)
                            .frame(minWidth: geometry.size.width, alignment: .leading)
                    }
                    }
                    if let selectedID = workspace.selectedID, workspace.layout(containing: selectedID).leaves.count > 1 {
                        Button { if workspace.broadcastTabID == nil { workspace.beginBroadcast() } else { workspace.endBroadcast() } } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(workspace.broadcastTabID == nil ? Color.secondary : Color.orange)
                        }.buttonStyle(.plain).frame(width: 28, height: 28).help("广播命令")
                    }
                    Group {
                        if let session = workspace.selected {
                            TerminalSFTPButton(session: session, preferDetached: workspace.layout(containing: session.id).leaves.count > 1)
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }.frame(width: 32, height: 28)
                    Menu { newSessionActions } label: { Image(systemName: "plus") }
                        .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).help("选择新会话类型")
                }.frame(height: 30).background(Color(nsColor: .windowBackgroundColor))
                Divider()
        HSplitView {
            if workspace.sidebarVisible {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").font(.title2).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MyTerm").font(.title3.bold())
                        Text("你的服务器工作台").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
                TextField("搜索服务器或分组", text: $workspace.search).textFieldStyle(.roundedBorder)
                Button(action: { workspace.newLocal() }) {
                    Label("本地终端", systemImage: "terminal").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
                Button { workspace.importPresented = true } label: { Label("从 SSH 配置导入…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.plain)
                HStack {
                    Text("SSH 服务器").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button { workspace.editGroup() } label: { Image(systemName: "folder.badge.plus") }
                        .buttonStyle(.plain).help("新建会话分组")
                    Button { workspace.editor = Server() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help("添加服务器 ⌘N")
                }
                ScrollView { ServerGroupsView(workspace: workspace) }
                Menu {
                    Button("保存当前会话…", action: workspace.saveSession)
                    Button("导入会话配置…", action: workspace.importSessions)
                    Button("导出会话配置…", action: workspace.exportSessions)
                    Button("SSH 配置检查与导出…", action: workspace.showSSHConfigurationAudit)
                    Divider()
                    ForEach(workspace.savedSessions) { saved in
                        Menu("\(saved.name)（\(saved.tabs.count) 个会话）") {
                            Button("恢复") { workspace.restore(saved) }
                            Button("重命名…") { workspace.renameSaved(saved) }
                            Button("用当前标签配置更新") { workspace.updateSaved(saved) }
                            Button("删除", role: .destructive) { workspace.deleteSaved(saved) }
                        }
                    }
                } label: { Label("保存与恢复会话", systemImage: "rectangle.stack") }
                Button(action: workspace.showHistory) { Label("会话历史与导出…", systemImage: "clock.arrow.circlepath") }
                Spacer(minLength: 0)
                Text("⌘T 新终端   ·   ⌘N 添加服务器")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                .background(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea(.container, edges: .top)
            }
            VStack(spacing: 0) {
                if let selected = workspace.selected {
                    SplitPaneView(workspace: workspace, layout: workspace.layout(containing: selected.id))
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "terminal").font(.system(size: 44)).foregroundStyle(.mint)
                        Text("开始一个新会话").font(.title2)
                        Text("新建 SSH 会话、连接已保存的服务器，或打开本地终端。").foregroundStyle(.secondary)
                        HStack {
                            Button("新建 SSH 会话…") { workspace.editor = Server() }.buttonStyle(.borderedProminent)
                            if !workspace.servers.isEmpty {
                                Menu("连接已保存的服务器") {
                                    ForEach(workspace.servers) { server in
                                        Button(server.displayName) { workspace.connect(server) }
                                    }
                                }.fixedSize()
                            }
                            Button("打开本地终端", action: { workspace.newLocal() }).buttonStyle(.bordered)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
                }
            }.frame(minWidth: 600).ignoresSafeArea(.container, edges: .top)
        }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if workspace.groupRecoveryRequired {
                HStack(spacing: 12) {
                    Text("分组信息异常，请修复或移除。服务器会话不受影响。")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("修复分组", action: workspace.repairGroupFile).fixedSize()
                    Button("移除分组", action: workspace.removeGroupFile).fixedSize()
                }.padding(12).background(.orange.opacity(0.12))
            }
        }
        .onChange(of: workspace.editor) { _, server in
            if let server { ServerEditorWindowController.shared.present(server: server, workspace: workspace) }
        }
        .sheet(item: $workspace.splitRequest) { SplitSessionChooser(workspace: workspace, request: $0) }
        .sheet(isPresented: $workspace.importPresented) { SSHImportView(workspace: workspace) }
        .sheet(isPresented: $workspace.historyPresented) { HistoryView(model: workspace.history, refresh: workspace.showHistory) }
        .preferredColorScheme(theme.scheme)
        .environment(\.locale, interfaceLanguage.locale)
        .alert("MyTerm", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("好") { workspace.error = nil }
        } message: { Text(L10n.text(workspace.error ?? "")) }
    }
}

struct TerminalStatusBarButton: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        HStack(spacing: 4) {
        TabBarButton(symbol: "rectangle.bottomthird.inset.filled", tooltip: "展开 / 收起底部状态栏", identifier: "tabbar.status", selected: session.statusBarVisible) {
            session.statusBarVisible.toggle()
        }.frame(width: 28, height: 28).contentShape(Rectangle())
        }.padding(.trailing, 4)
    }
}

/// Observe the session here: its SFTP model arrives after asynchronous SSH setup.
/// Keep the shortcut present even while the model is being prepared or reconnected.
struct TerminalSFTPButton: View {
    @ObservedObject var session: TerminalSession
    var preferDetached = false
    var body: some View {
        if session.sourceServer != nil {
            TabBarButton(symbol: "sidebar.right", tooltip: "展开 / 收起 SFTP 文件面板", identifier: "tabbar.sftp", selected: session.showSFTP) {
                if let model = session.sftp, model.detached || preferDetached {
                    session.showSFTP = true
                    model.showWindow()
                } else { session.showSFTP.toggle() }
            }.frame(width: 28, height: 28).contentShape(Rectangle())
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}

struct TerminalPane: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var session: TerminalSession
    var isFocused = true
    var isSplit = false
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                TerminalSurface(session: session, isFocused: isFocused).frame(minWidth: 220)
                if session.showSFTP, !isSplit, let sftp = session.sftp {
                    SFTPInlinePanel(model: sftp).background(Color(nsColor: .windowBackgroundColor))
                }
            }
            if let bridge = session.codexExecutionBridge, let target = session.codexTargetSessionID {
                CodexExecutionBar(bridge: bridge, sessionID: target, codexTabID: session.id)
            }
            if let bridge = session.terminal.zmodem { ZmodemStatusView(bridge: bridge) }
            if session.statusBarVisible || !session.isRunning {
            Divider()
            TerminalStatusBar(session: session)
            }
        }
        .onAppear { if isSplit && session.showSFTP { session.sftp?.showWindow() } }
        .onChange(of: session.showSFTP) { _, shown in if isSplit && shown { session.sftp?.showWindow() } }
        .onReceive(session.$sftp) { model in if isSplit && session.showSFTP { model?.showWindow() } }
    }
}

struct ServerEditor: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject private var draft: ServerDraft
    @ObservedObject var workspace: Workspace
    @ObservedObject var theme = ThemePreferences.shared
    let onClose: () -> Void
    let onZoom: () -> Void
    init(server: Server, workspace: Workspace, onClose: @escaping () -> Void, onZoom: @escaping () -> Void) {
        self.workspace = workspace
        self.onClose = onClose; self.onZoom = onZoom
        _draft = StateObject(wrappedValue: ServerDraft(server: server))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("SSH 服务器").font(.title2.bold())
                Spacer()
                Button("最大化 / 还原", action: onZoom)
            }.layoutPriority(1)
            ScrollView(.vertical) { VStack(alignment: .leading, spacing: 14) {
                EditorTextField(title: "名称", text: $draft.server.name, prompt: "例如：开发服务器")
                EditorTextField(title: "主机", text: $draft.server.host, prompt: "IP、域名或 SSH 别名")
                EditorTextField(title: "用户名", text: $draft.server.user, prompt: "留空使用 SSH 配置")
                EditorTextField(title: "端口", text: $draft.server.port, prompt: "留空使用 SSH 配置 / 22")
                ServerAuthenticationEditor(draft: draft)
                HStack {
                    Toggle("详细配置跳板机", isOn: $draft.detailedJumps)
                    Button("跳板机管理…", action: workspace.showJumpManager)
                }
                if draft.detailedJumps {
                    Text("按顺序经过下列跳板机，再连接目标服务器。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Menu("选择已有跳板配置") {
                        ForEach(SSHJumpPreset.available(in: workspace.servers)) { preset in
                            Button(preset.name) { draft.useJumpPreset(preset) }
                        }
                    }.disabled(SSHJumpPreset.available(in: workspace.servers).isEmpty)
                    Text("选择后引用公共跳板机并替换当前路径和代理。修改公共配置会影响引用它的会话；可先解除关联再单独修改。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach($draft.jumpServers) { $hop in
                        if let profileID = hop.profileID {
                            Text(L10n.text("公共跳板机 · 引用会话：") + workspace.jumpReferences(profileID).joined(separator: "、"))
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            Button("另存为独立跳板配置") { hop.profileID = UUID() }
                        }
                        Menu("更换跳板机") {
                            ForEach(workspace.sharedJumpProfiles) { profile in
                                Button(workspace.sharedJumpTitle(profile)) {
                                    var replacement = profile; replacement.id = hop.id
                                    draft.jumpPasswords.removeValue(forKey: hop.id)
                                    hop = replacement
                                }
                            }
                        }.disabled(workspace.sharedJumpProfiles.isEmpty)
                        SSHJumpEditor(hop: $hop, password: Binding(get: { draft.jumpPasswords[hop.id] ?? "" }, set: { draft.jumpPasswords[hop.id] = $0 }), position: (draft.jumpServers.firstIndex(where: { $0.id == hop.id }) ?? 0) + 1,
                                      moveUp: { draft.moveJump(hop.id, offset: -1) }, moveDown: { draft.moveJump(hop.id, offset: 1) },
                                      remove: { draft.jumpServers.removeAll { $0.id == hop.id } })
                    }
                    Menu("选择已有跳板机") {
                        ForEach(workspace.sharedJumpProfiles) { profile in
                            Button(workspace.sharedJumpTitle(profile)) {
                                var row = profile; row.id = UUID(); draft.jumpServers.append(row)
                            }
                        }
                    }.disabled(workspace.sharedJumpProfiles.isEmpty || draft.jumpServers.count >= 10)
                    Button("添加一级跳板机") { draft.jumpServers.append(SSHJumpServer()) }.disabled(draft.jumpServers.count >= 10)
                } else {
                    EditorTextField(title: "跳板机", text: $draft.jumpHost, prompt: "B 别名或 user@B:22；多级用逗号分隔")
                }
                Picker("X11 转发", selection: Binding(get: { draft.server.x11Forwarding ?? .disabled }, set: { draft.server.x11Forwarding = $0 })) {
                    Text("关闭").tag(X11Forwarding.disabled)
                    Text("普通转发（-X）").tag(X11Forwarding.untrusted)
                    Text("受信任转发（-Y）").tag(X11Forwarding.trusted)
                }
                Text("需要本机运行 XQuartz、远端允许 X11Forwarding。受信任模式仅用于可信服务器，远端程序可访问本地 X server。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("SSH 压缩（节省带宽）", isOn: $draft.compression)
                Toggle("trzsz 文件传输（支持 tmux）", isOn: Binding(get: { draft.server.trzszEnabled ?? true }, set: { draft.server.trzszEnabled = $0 }))
                if draft.server.trzszEnabled ?? true {
                    Picker("拖拽上传协议", selection: Binding(get: { draft.server.dragUploadProtocol ?? .automatic }, set: { draft.server.dragUploadProtocol = $0 })) {
                        Text("自动（全屏终端用 trzsz）").tag(DragUploadProtocol.automatic)
                        Text("trzsz").tag(DragUploadProtocol.trzsz)
                        Text("ZMODEM").tag(DragUploadProtocol.zmodem)
                    }
                    Text("远端需安装 trz/tsz。在 shell 提示符下执行 trz 上传、tsz 文件名下载；拖拽时也请停留在 shell 提示符。进度显示在终端中，Ctrl+C 取消。保存后重新打开连接生效。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Picker("会话日志", selection: Binding(get: { draft.server.historyLogging ?? .inherit }, set: { draft.server.historyLogging = $0 })) {
                    ForEach(HistoryLoggingMode.allCases, id: \.self) { mode in Text(L10n.text(mode.title)).tag(mode) }
                }
                Text("此选择随 SSH 配置保存，对新连接生效。当前标签可右键 → 会话日志即时调整。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("SSH 连接调试（-vvv）", isOn: Binding(get: { draft.server.debugLogging ?? false }, set: { draft.server.debugLogging = $0 }))
                Text("默认关闭。开启后，详细连接日志显示在终端中；保存后重新打开该 SSH 会话生效。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("通过网络代理连接", isOn: $draft.proxyEnabled)
                if draft.proxyEnabled {
                    Picker("代理类型", selection: $draft.proxyKind) {
                        Text("HTTP CONNECT").tag(ProxyKind.http)
                        Text("SOCKS5").tag(ProxyKind.socks5)
                    }
                    EditorTextField(title: "代理地址", text: $draft.proxyHost)
                    EditorTextField(title: "代理端口", text: $draft.proxyPort)
                    Text("支持无认证代理；设置跳板机时，代理连接第一台跳板机。跳板机自身的密钥等设置使用 SSH 配置中的别名。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack { Text("端口转发").font(.headline); Spacer(); Button("添加") { draft.forwards.append(PortForward()) } }
                ForEach($draft.forwards) { $forward in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Spacer()
                            Button("删除转发", systemImage: "trash") { draft.removeForward(id: forward.id) }
                                .fixedSize()
                                .help("删除此条端口转发，保存后生效")
                        }
                        HStack {
                            Picker("类型", selection: $forward.kind) {
                                Text("本地 → 远端").tag(ForwardKind.local)
                                Text("远端 → 本地").tag(ForwardKind.remote)
                                Text("动态 SOCKS5").tag(ForwardKind.dynamic)
                            }
                        }
                        HStack(alignment: .top, spacing: 16) {
                            EditorTextField(title: "监听地址", text: $forward.bindAddress)
                            EditorTextField(title: "监听端口", text: $forward.listenPort).frame(width: 160)
                        }
                        if forward.kind != .dynamic {
                            HStack(alignment: .top, spacing: 16) {
                                EditorTextField(title: "目标主机", text: $forward.destinationHost)
                                EditorTextField(title: "目标端口", text: $forward.destinationPort).frame(width: 160)
                            }
                        }
                    }.padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                Text("转发随此 SSH 会话启动和关闭；远程转发是否允许外部访问取决于服务器配置。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8).padding(.bottom, 12)
                .background(EditorScrollbars())
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("目标服务器和跳板机密码均可提前填写，也可在连接时输入。密钥口令和验证码不自动保存。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let validationError = draft.validationError { Text(L10n.text(validationError)).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("取消") { onClose() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save(connect: false) }
                Button("保存并连接") { save(connect: true) }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(minWidth: 640, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
            .preferredColorScheme(theme.scheme)
            .environment(\.locale, interfaceLanguage.locale)
    }

    private func save(connect: Bool) {
        do {
            let validated = try draft.server.validated()
            guard workspace.confirmSharedJumpChanges(validated) else { return }
            if workspace.save(validated, password: draft.authentication == .password ? draft.password : "", jumpPasswords: draft.jumpPasswords) {
                if connect { workspace.connect(validated) }
                onClose()
            } else {
                draft.validationError = workspace.error
                workspace.error = nil
            }
        } catch { draft.validationError = error.localizedDescription }
    }


}

final class ServerDraft: ObservableObject {
    @Published var server: Server
    @Published var validationError: String?
    @Published var password = "" // Editor-only; never serialize secrets into Server.
    @Published var jumpPasswords: [UUID: String] = [:]
    func useJumpPreset(_ preset: SSHJumpPreset) {
        jumpPasswords.removeAll()
        server.jumpHost = nil
        server.jumpServers = preset.copiedHops()
        server.proxy = preset.proxy
    }
    init(server: Server) { self.server = server }
    var jumpHost: String { get { server.jumpHost ?? "" } set { server.jumpHost = newValue.isEmpty ? nil : newValue } }
    var detailedJumps: Bool {
        get { server.jumpServers != nil }
        set { server.jumpServers = newValue ? (server.jumpServers ?? [SSHJumpServer()]) : nil; if newValue { server.jumpHost = nil } }
    }
    var jumpServers: [SSHJumpServer] { get { server.jumpServers ?? [] } set { server.jumpServers = newValue } }
    func moveJump(_ id: UUID, offset: Int) {
        var hops = jumpServers
        guard let index = hops.firstIndex(where: { $0.id == id }), hops.indices.contains(index + offset) else { return }
        hops.swapAt(index, index + offset); jumpServers = hops
    }
    var authentication: AuthenticationMode { get { server.authentication ?? .automatic } set { server.authentication = newValue } }
    var compression: Bool { get { server.compression ?? true } set { server.compression = newValue } }
    var proxyEnabled: Bool { get { server.proxy != nil } set { server.proxy = newValue ? (server.proxy ?? NetworkProxy()) : nil } }
    var proxyKind: ProxyKind { get { server.proxy?.kind ?? .socks5 } set { server.proxy?.kind = newValue } }
    var proxyHost: String { get { server.proxy?.host ?? "" } set { server.proxy?.host = newValue } }
    var proxyPort: String { get { server.proxy?.port ?? "" } set { server.proxy?.port = newValue } }
    var forwards: [PortForward] { get { server.forwards ?? [] } set { server.forwards = newValue } }
    func removeForward(id: UUID) { forwards.removeAll { $0.id == id } }
}
