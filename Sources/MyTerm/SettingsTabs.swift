import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable {
    case language, theme, highlighting, terminal, passwords, keys
    var symbol: String {
        switch self {
        case .language: return "globe"
        case .theme: return "paintpalette"
        case .highlighting: return "highlighter"
        case .terminal: return "terminal"
        case .passwords: return "lock"
        case .keys: return "key"
        }
    }
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

/// Persistent sidebar navigation; all categories remain visible after locale changes.
struct SettingsNavigationButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let identifier: String
    let selected: Bool
    let action: () -> Void
    func makeNSView(context: Context) -> SettingsNativeTab {
        let button = SettingsNativeTab()
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.cell?.wraps = true
        button.cell?.usesSingleLineMode = false
        button.cell?.lineBreakMode = .byWordWrapping
        button.target = button; button.action = #selector(SettingsNativeTab.selectTab)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsNativeTab, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 184, height: 48)
    }
    func updateNSView(_ button: SettingsNativeTab, context: Context) {
        button.title = L10n.text(title)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = selected ? .white : .labelColor
        button.layer?.backgroundColor = (selected ? NSColor.controlAccentColor : .clear).cgColor
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
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
