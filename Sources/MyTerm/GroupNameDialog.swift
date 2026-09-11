import AppKit
import MyTermCore

/// Keeps the user's input available when a group cannot be saved.
final class GroupNameDialog {
    let alert = NSAlert()
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))

    init(name: String?) {
        alert.messageText = L10n.text(name == nil ? "新建会话分组" : "重命名分组")
        alert.informativeText = L10n.text("例如：生产环境、测试环境、客户项目。")
        field.stringValue = name ?? ""
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.placeholderString = L10n.text("分组名称（1–60 个字符）")
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("保存"))
        alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
    }

    func run(save: (String) throws -> Void) {
        while alert.runModal() == .alertFirstButtonReturn {
            // Commit any active input-method composition before reading the final text.
            (field.currentEditor() as? NSTextView)?.unmarkText()
            let text = field.currentEditor()?.string ?? field.stringValue
            alert.window.makeFirstResponder(nil)
            field.stringValue = SessionGroup.normalizedName(text)
            do {
                try save(field.stringValue)
                return
            } catch {
                alert.informativeText = L10n.text(error.localizedDescription)
                alert.window.initialFirstResponder = field
            }
        }
    }
}
