import SwiftUI
import MyTermCore

private final class CredentialSettingsState: ObservableObject {
    @Published var message = ""
    @Published var entries: [StoredPasswordInfo] = []
    private let store = SQLitePasswordStore()
    func refresh() {
        do { entries = try store.list() }
        catch { message = error.localizedDescription }
    }
    func update(_ entry: StoredPasswordInfo) {
        let alert = NSAlert(); alert.messageText = L10n.text("更新已保存密码")
        alert.informativeText = entry.label + "\n仅更新本地记录，不修改服务器密码；下次认证时使用。"
        let field = NSSecureTextField(); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        defer { field.stringValue = "" }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !field.stringValue.isEmpty else { message = "密码不能为空。"; return }
        do { try store.save(field.stringValue, account: entry.id); message = "密码已更新，下次连接生效。" }
        catch { message = error.localizedDescription }
    }
    func delete(_ entry: StoredPasswordInfo) {
        do { try store.delete(entry.id); refresh(); message = "已删除所选密码。" }
        catch { message = error.localizedDescription }
    }
    func clear() {
        let alert = NSAlert(); alert.messageText = L10n.text("清除所有已保存的 SSH 密码？")
        alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("清除"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try store.deleteAll(); refresh(); message = "已清除 MyTerm 保存的 SSH 密码。" }
        catch { message = error.localizedDescription }
    }
}
struct CredentialSettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject private var state = CredentialSettingsState()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("SSH 密码管理").font(.title2.bold()); Spacer(); Button("刷新", action: state.refresh) }
            Text("认证成功后记住密码。可更新或删除本地记录，密码不会显示在列表中。旧版记录没有账号描述，使用编号标识。")
                .font(.caption).foregroundStyle(.secondary)
            List(state.entries) { entry in
                VStack(alignment: .leading) {
                    Text(entry.label).lineLimit(2)
                    HStack {
                        Button("更新密码…") { state.update(entry) }
                        Button("删除", role: .destructive) { state.delete(entry) }
                    }
                }.padding(.vertical, 4)
            }
            if state.entries.isEmpty { Text("暂无已保存的密码").foregroundStyle(.secondary) }
            Button("清除所有已记住的 SSH 密码", role: .destructive, action: state.clear)
            Text(L10n.text(state.message)).font(.caption)
        }.padding(24).onAppear(perform: state.refresh)
    }
}
