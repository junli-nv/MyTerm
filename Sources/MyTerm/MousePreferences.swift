import AppKit
import SwiftUI

final class MousePreferences: ObservableObject {
    static let shared = MousePreferences()
    private let defaults: UserDefaults
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
        disableBell = defaults.bool(forKey: "terminal.disableBell")
        rightClickPastes = defaults.bool(forKey: "mouse.rightClickPastes")
        copyOnSelection = defaults.bool(forKey: "mouse.copyOnSelection")
    }
}

final class MouseSettingsController: NSWindowController {
    static let shared = MouseSettingsController()
    private var languageObserver: NSObjectProtocol?
    let selection = SettingsSelection()
    deinit { if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) } }
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("MyTerm 设置")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(selection: selection))
        languageObserver = NotificationCenter.default.addObserver(forName: LanguagePreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L10n.text("MyTerm 设置")
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var theme = ThemePreferences.shared
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    SettingsTabButton(page: page, selected: selection.page == page) { selection.page = page }
                        .frame(width: (760.0 - 24 - 30) / 6, height: 42)
                }
            }
            Divider()
            Group {
                switch selection.page {
                case .language: LanguageSettingsView()
                case .theme: ThemeSettingsView()
                case .highlighting: OutputHighlightSettingsView()
                case .terminal: MouseSettingsView()
                case .passwords: CredentialSettingsView()
                case .keys: SSHKeySettingsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(12).frame(width: 760, height: 620).preferredColorScheme(theme.scheme)
            .environment(\.locale, interfaceLanguage.locale)
    }
}

private struct MouseSettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject private var preferences = MousePreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("鼠标与响铃").font(.title2.bold())
            Toggle("选中文本后自动复制", isOn: $preferences.copyOnSelection)
            Toggle("右键直接粘贴", isOn: $preferences.rightClickPastes)
            Text("开启后，按住 Shift 再右键仍可打开菜单。\n⌘C 复制、⌘V 粘贴始终可用。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("禁用终端响铃", isOn: $preferences.disableBell)
            Text("关闭本地 shell 和 SSH 的 BEL 响铃提示，默认禁用。")
                .font(.callout).foregroundStyle(.secondary)
            Text("设置立即应用到所有终端，并在下次启动时保留。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 440, alignment: .leading)
    }
}
