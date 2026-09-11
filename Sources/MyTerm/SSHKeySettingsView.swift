import SwiftUI
import MyTermCore

private final class SSHKeySettingsState: ObservableObject {
    @Published var keys: [ManagedSSHKey] = []
    @Published var message = ""
    private let library = SSHKeyLibrary()
    func refresh() {
        do { keys = try library.list() } catch { message = error.localizedDescription }
    }
    func importKey() {
        let panel = NSOpenPanel(); panel.title = L10n.text("导入 SSH 私钥")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.importKey(url); refresh(); message = "已复制到应用密钥库，原文件保持不变。" }
        catch { message = error.localizedDescription }
    }
    func showPublic(_ key: ManagedSSHKey) {
        do {
            let text = try String(contentsOfFile: key.url.path + ".pub", encoding: .utf8)
            let alert = NSAlert(); alert.messageText = key.name + " 公钥"
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
            view.string = text; view.isEditable = false; view.isSelectable = true
            alert.accessoryView = view; alert.runModal()
        } catch { message = "此密钥没有附带 .pub 公钥文件。可将同名 .pub 放在原私钥旁后重新导入。" }
    }
    func delete(_ key: ManagedSSHKey) {
        let alert = NSAlert(); alert.messageText = "删除应用内密钥 \(key.name)？"
        alert.informativeText = L10n.text("使用此路径的会话将无法再用该密钥认证，原始文件不受影响。")
        alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("删除"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try library.delete(key); refresh(); message = "已删除应用内副本。" }
        catch { message = error.localizedDescription }
    }
}
struct SSHKeySettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject private var state = SSHKeySettingsState()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH 密钥管理").font(.title2.bold()); Spacer()
                Button("导入私钥…", action: state.importKey)
                Button("刷新", action: state.refresh)
            }
            Text("支持 ssh-keygen 的 OpenSSH / PEM 私钥，包括有口令的密钥。按原格式复制，口令仍在连接时输入；同名 .pub 文件会一并导入。也可在 SSH 配置中直接选用 ~/.ssh 的原文件。")
                .font(.caption).foregroundStyle(.secondary)
            List(state.keys) { key in
                VStack(alignment: .leading) {
                    Text(key.name)
                    Text(key.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("查看公钥") { state.showPublic(key) }
                        Button("删除", role: .destructive) { state.delete(key) }
                    }
                }.padding(.vertical, 4)
            }
            if state.keys.isEmpty { Text("暂无导入的密钥").foregroundStyle(.secondary) }
            Text(L10n.text(state.message)).font(.caption)
        }.padding(24).onAppear(perform: state.refresh)
    }
}
