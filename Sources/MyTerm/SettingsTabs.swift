import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable {
    case language, theme, highlighting, terminal, passwords, keys
    var title: String {
        switch self {
        case .language: return "语言"
        case .theme: return "主题与字体"
        case .highlighting: return "输出着色"
        case .terminal: return "终端行为"
        case .passwords: return "SSH 密码"
        case .keys: return "SSH 密钥"
        }
    }
}
final class SettingsSelection: ObservableObject { @Published var page = SettingsPage.language }

/// Explicit, equal-width tabs: no adaptive overflow menu during locale changes.
struct SettingsTabButton: NSViewRepresentable {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void
    func makeNSView(context: Context) -> SettingsNativeTab {
        let button = SettingsNativeTab()
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.cell?.wraps = true
        button.cell?.usesSingleLineMode = false
        button.cell?.lineBreakMode = .byWordWrapping
        button.target = button; button.action = #selector(SettingsNativeTab.selectTab)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsNativeTab, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 117, height: 42)
    }
    func updateNSView(_ button: SettingsNativeTab, context: Context) {
        button.title = L10n.text(page.title)
        button.identifier = NSUserInterfaceItemIdentifier("settings.tab." + page.rawValue)
        button.setAccessibilityLabel(button.title)
        button.state = selected ? .on : .off
        button.onSelect = action
    }
}
final class SettingsNativeTab: NSButton {
    var onSelect: (() -> Void)?
    @objc func selectTab() { onSelect?() }
}

struct ThemeSettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(L10n.text(title)).fixedSize(horizontal: false, vertical: true)
                .frame(width: 160, alignment: .leading).padding(.top, 4)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
