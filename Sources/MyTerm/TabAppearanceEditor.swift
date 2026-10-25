import AppKit
import SwiftUI
import MyTermCore

extension TabColor {
    var nsColor: NSColor {
        switch self {
        case .automatic: return .secondaryLabelColor
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }
}

struct TabAppearanceEditor: View {
    @Binding var appearance: TabAppearance
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签颜色与环境标识").font(.headline)
            TextField("环境标识（例如 PROD / TEST，最多 24 字）", text: $appearance.environment)
            Picker("标签颜色", selection: $appearance.color) {
                ForEach(TabColor.allCases, id: \.self) { color in Text(L10n.text(color.title)).tag(color) }
            }
            Text("仅用于视觉区分，不改变连接目标或执行权限。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SessionEnvironmentBadge: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        HStack(spacing: 4) {
            if session.appearance.color != .automatic {
                Circle().fill(Color(nsColor: session.appearance.color.nsColor)).frame(width: 7, height: 7)
            }
            if !session.appearance.environment.isEmpty {
                Text(session.appearance.environment).font(.caption.bold()).lineLimit(1)
                    .padding(.horizontal, 4).background(Color(nsColor: session.appearance.color.nsColor).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }.help(session.appearance.environment)
    }
}

extension Workspace {
    func editTabAppearance(_ session: TerminalSession) {
        let alert = NSAlert(); alert.messageText = L10n.text("标签颜色与环境标识")
        alert.informativeText = L10n.text("已保存的 SSH 配置会记住标识；其他标签随保存的会话一起保留。")
        let field = NSTextField(string: session.appearance.environment)
        field.placeholderString = L10n.text("环境标识（例如 PROD / TEST，最多 24 字）")
        field.frame = NSRect(x: 0, y: 40, width: 360, height: 24)
        let colors = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        colors.addItems(withTitles: TabColor.allCases.map { L10n.text($0.title) })
        colors.selectItem(at: TabColor.allCases.firstIndex(of: session.appearance.color) ?? 0)
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 70))
        form.addSubview(field); form.addSubview(colors); alert.accessoryView = form
        alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setTabAppearance(TabAppearance(color: TabColor.allCases[max(0, colors.indexOfSelectedItem)], environment: field.stringValue), for: session)
    }
    func setTabAppearance(_ value: TabAppearance, for session: TerminalSession) {
        do {
            let value = try value.validated()
            if let id = session.sourceServer?.id, var saved = servers.first(where: { $0.id == id }) {
                saved.tabAppearance = value
                guard save(saved) else { return }
            } else { session.setAppearance(value) }
            objectWillChange.send()
        } catch { self.error = error.localizedDescription }
    }
}
