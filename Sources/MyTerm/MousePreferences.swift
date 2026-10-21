import AppKit
import SwiftUI

final class MousePreferences: ObservableObject {
    static let shared = MousePreferences()
    private let defaults: UserDefaults
    @Published var fullscreenScroll: FullscreenScrollMode {
        didSet { defaults.set(fullscreenScroll.rawValue, forKey: "mouse.fullscreenScroll") }
    }
    @Published var disableBell: Bool {
        didSet { defaults.set(disableBell, forKey: "terminal.disableBell") }
    }
    @Published var rightClickPastes: Bool {
        didSet { defaults.set(rightClickPastes, forKey: "mouse.rightClickPastes") }
    }
    @Published var copyOnSelection: Bool {
        didSet { defaults.set(copyOnSelection, forKey: "mouse.copyOnSelection") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["mouse.rightClickPastes": true, "mouse.copyOnSelection": true, "terminal.disableBell": true])
        fullscreenScroll = FullscreenScrollMode(rawValue: defaults.string(forKey: "mouse.fullscreenScroll") ?? "") ?? .fast
        disableBell = defaults.bool(forKey: "terminal.disableBell")
        rightClickPastes = defaults.bool(forKey: "mouse.rightClickPastes")
        copyOnSelection = defaults.bool(forKey: "mouse.copyOnSelection")
    }
}

final class MouseSettingsController: NSWindowController, NSWindowDelegate {
    static let shared = MouseSettingsController()
    private var languageObserver: NSObjectProtocol?
    let selection = SettingsSelection()
    deinit { if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) } }
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.text("MyTerm 设置")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 940, height: 620)
        window.collectionBehavior.formUnion([.fullScreenPrimary, .moveToActiveSpace])
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(selection: selection))
        languageObserver = NotificationCenter.default.addObserver(forName: LanguagePreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L10n.text("MyTerm 设置")
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) { selection.workspace?.jumpTest.cancel() }

    func present(page: SettingsPage? = nil, workspace: Workspace? = nil) {
        if let active = workspace ?? (NSApp.delegate as? AppDelegate)?.workspace { selection.workspace = active }
        if let page { selection.page = page }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var theme = ThemePreferences.shared
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    SettingsNavigationButton(title: page.title, symbol: page.symbol, identifier: "settings.tab." + page.rawValue, selected: selection.page == page) { selection.page = page }
                        .frame(width: 184, height: 48)
                }
                Spacer(minLength: 0)
            }.padding(12).frame(width: 208)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            Group {
                switch selection.page {
                case .language: LanguageSettingsView()
                case .theme: ThemeSettingsView()
                case .highlighting: OutputHighlightSettingsView()
                case .terminal: MouseSettingsView()
                case .passwords: CredentialSettingsView()
                case .keys: SSHKeySettingsView()
                case .jumps:
                    if let workspace = selection.workspace { SharedJumpManagerView(workspace: workspace, test: workspace.jumpTest) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 940, minHeight: 620).preferredColorScheme(theme.scheme)
            .environment(\.locale, interfaceLanguage.locale)
    }
}

private struct MouseSettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject private var preferences = MousePreferences.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("鼠标与响铃").font(.title2.bold())
            Toggle("选中文本后自动复制", isOn: $preferences.copyOnSelection)
            Toggle("右键直接粘贴", isOn: $preferences.rightClickPastes)
            Text("开启后，按住 Shift 再右键仍可打开菜单。\n⌘C 复制、⌘V 粘贴始终可用。")
                .font(.callout).foregroundStyle(.secondary)
            Picker("全屏终端触摸板", selection: $preferences.fullscreenScroll) {
                ForEach(FullscreenScrollMode.allCases, id: \.self) { mode in Text(L10n.text(mode.title)).tag(mode) }
            }
            Text("默认快速滚动（4 倍）。按页模式发送 Page Up / Page Down，适合进入 tmux 复制模式后翻阅。此设置也影响其他全屏程序；普通 Shell 历史、鼠标滚轮和 Ctrl 字体缩放不变。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("禁用终端响铃", isOn: $preferences.disableBell)
            Text("关闭本地 shell 和 SSH 的 BEL 响铃提示，默认禁用。")
                .font(.callout).foregroundStyle(.secondary)
            Text("设置立即应用到所有终端，并在下次启动时保留。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            SplitShortcutSettingsView()
            Divider()
            HistorySettingsView()
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
