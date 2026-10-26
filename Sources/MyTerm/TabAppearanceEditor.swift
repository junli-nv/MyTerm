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
    func editTab(_ session: TerminalSession) {
        selectedID = session.id
        let alert = NSAlert(); alert.messageText = L10n.text("编辑标签")
        alert.informativeText = L10n.text("名称仅修改当前标签；颜色与环境标识同步到已保存的 SSH 配置及引用它的标签。其他标签随保存的会话一起保留。")
        let name = NSTextField(string: session.label)
        name.identifier = NSUserInterfaceItemIdentifier("tab.editor.name")
        let environment = NSTextField(string: session.appearance.environment)
        environment.identifier = NSUserInterfaceItemIdentifier("tab.editor.environment")
        environment.toolTip = L10n.text("环境标识（例如 PROD / TEST，最多 24 字）")
        let colors = NSPopUpButton()
        colors.identifier = NSUserInterfaceItemIdentifier("tab.editor.color")
        colors.addItems(withTitles: TabColor.allCases.map { L10n.text($0.title) })
        colors.selectItem(at: TabColor.allCases.firstIndex(of: session.appearance.color) ?? 0)
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 108))
        for (index, row) in [("标签名称", name as NSView), ("环境标识", environment as NSView), ("标签颜色", colors as NSView)].enumerated() {
            let y = CGFloat(2 - index) * 36
            let label = NSTextField(labelWithString: L10n.text(row.0))
            label.frame = NSRect(x: 0, y: y + 3, width: 110, height: 24)
            row.1.frame = NSRect(x: 116, y: y, width: 324, height: 28)
            form.addSubview(label); form.addSubview(row.1)
        }
        alert.accessoryView = form
        alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        updateTab(session, name: name.stringValue, appearance: TabAppearance(
            color: TabColor.allCases[max(0, colors.indexOfSelectedItem)], environment: environment.stringValue))
    }
    /// Validate and persist metadata before renaming, so a failed save changes neither field.
    func updateTab(_ session: TerminalSession, name: String, appearance: TabAppearance) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请输入标签名称。"; return }
        let validated: TabAppearance
        do { validated = try appearance.validated() }
        catch { self.error = error.localizedDescription; return }
        guard validated == session.appearance || setTabAppearance(validated, for: session) else { return }
        objectWillChange.send(); session.label = name
    }
    @discardableResult
    func setTabAppearance(_ value: TabAppearance, for session: TerminalSession) -> Bool {
        do {
            let value = try value.validated()
            if let id = session.sourceServer?.id, var saved = servers.first(where: { $0.id == id }) {
                saved.tabAppearance = value
                guard save(saved) else { return false }
            } else { session.setAppearance(value) }
            objectWillChange.send()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
