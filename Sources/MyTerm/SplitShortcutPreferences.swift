import SwiftUI
import AppKit
import MyTermCore

extension SplitKeyBinding {
    var modifiers: NSEvent.ModifierFlags {
        var value: NSEvent.ModifierFlags = [.command]
        if shift { value.insert(.shift) }; if control { value.insert(.control) }; if option { value.insert(.option) }
        return value
    }
    var display: String { (control ? "⌃" : "") + (option ? "⌥" : "") + "⌘" + (shift ? "⇧" : "") + key.uppercased() }
}
final class SplitShortcutPreferences: ObservableObject {
    static let shared = SplitShortcutPreferences()
    static let didChange = Notification.Name("MyTermSplitShortcutsChanged")
    static let storageKey = "terminal.splitShortcuts"
    @Published private(set) var value: SplitShortcuts
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(SplitShortcuts.self, from: $0) }
        value = decoded.flatMap { (try? $0.validate()) != nil ? $0 : nil } ?? SplitShortcuts()
    }
    func save(_ newValue: SplitShortcuts) throws {
        try newValue.validate()
        defaults.set(try JSONEncoder().encode(newValue), forKey: Self.storageKey)
        value = newValue
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
final class SplitShortcutDraft: ObservableObject {
    @Published var value = SplitShortcutPreferences.shared.value
    @Published var message: String?
}
struct SplitShortcutSettingsView: View {
    @StateObject private var draft = SplitShortcutDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分屏快捷键").font(.headline)
            Text("Command 为必选。选择修饰键并输入英文字母；保存后立即生效。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            row("上下分屏", binding: $draft.value.horizontal)
            row("左右分屏", binding: $draft.value.vertical)
            HStack {
                Button("保存快捷键") { save() }
                Button("恢复默认快捷键") { draft.value = SplitShortcuts(); save() }
            }
            if let message = draft.message { Text(L10n.text(message)).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func row(_ title: String, binding: Binding<SplitKeyBinding>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title) + "  " + binding.wrappedValue.display)
            HStack {
                Text("⌘")
                Toggle("Shift", isOn: binding.shift)
                Toggle("Control", isOn: binding.control)
                Toggle("Option", isOn: binding.option)
                TextField("A–Z", text: binding.key).frame(width: 50)
            }.toggleStyle(.checkbox)
        }
    }
    private func save() {
        draft.value.horizontal.key = draft.value.horizontal.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        draft.value.vertical.key = draft.value.vertical.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do { try SplitShortcutPreferences.shared.save(draft.value); draft.message = "快捷键已保存。" }
        catch { draft.message = error.localizedDescription }
    }
}

/// Route before terminal key handling, just like Control-Tab. The application
/// monitor limits this to its main window without a sheet; settings/editors keep
/// their own input. Menu items remain an alternate, discoverable entry point.
enum SplitShortcutDispatch {
    static func handle(_ event: NSEvent, workspace: Workspace) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let preferences = SplitShortcutPreferences.shared.value
        for (axis, binding) in [(PaneAxis.horizontal, preferences.horizontal), (.vertical, preferences.vertical)] {
            if modifiers == binding.modifiers && key == binding.key {
                if !event.isARepeat { workspace.requestSplit(axis) }
                return true
            }
        }
        return false
    }
}
