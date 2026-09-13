import SwiftUI
import MyTermCore

final class SSHKeySettingsState: ObservableObject {
    @Published var keys: [ManagedSSHKey] = []
    @Published var message = ""
    @Published var associations: [String: [String]] = [:]
    private let library: SSHKeyLibrary
    private let referenceProvider: () -> [SSHKeyReference]
    init(library: SSHKeyLibrary = SSHKeyLibrary(), references: @escaping () -> [SSHKeyReference] = SSHKeySettingsState.workspaceReferences) {
        self.library = library; referenceProvider = references
    }
    static func workspaceReferences() -> [SSHKeyReference] {
        guard let workspace = (NSApp.delegate as? AppDelegate)?.workspace else { return [] }
        var result = workspace.servers.flatMap { SSHKeyAssociations.references(server: $0, session: $0.displayName) }
        for saved in workspace.savedSessions {
            for tab in saved.tabs {
                if let server = tab.server { result += SSHKeyAssociations.references(server: server, session: saved.name + " / " + server.displayName) }
            }
        }
        for session in workspace.sessions {
            for server in [session.sourceServer, session.server].compactMap({ $0 }) {
                result += SSHKeyAssociations.references(server: server, session: L10n.text("已打开") + " · " + session.label)
            }
        }
        return result
    }
    func refresh() {
        do {
            keys = try library.list()
            let references = referenceProvider()
            associations = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, SSHKeyAssociations.matching($0, references: references)) })
        } catch { message = error.localizedDescription }
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
    /// Recheck immediately before deletion; list contents may be stale after editing a session.
    func delete(_ key: ManagedSSHKey, confirm: (Bool, [String]) -> Bool) throws {
        guard confirm(false, SSHKeyAssociations.matching(key, references: referenceProvider())) else { return }
        let affected = SSHKeyAssociations.matching(key, references: referenceProvider())
        if !affected.isEmpty {
            guard confirm(true, affected) else { return }
            // A modal alert runs the event loop. Do not delete if new references appeared meanwhile.
            let current = SSHKeyAssociations.matching(key, references: referenceProvider())
            guard Set(current).isSubset(of: Set(affected)) else {
                message = "密钥关联已变化，请重新检查后删除。"; refresh(); return
            }
        }
        try library.delete(key); refresh(); message = "已删除应用内副本。"
    }
    func delete(_ key: ManagedSSHKey) {
        do {
            try delete(key) { additional, affected in
                let alert = NSAlert()
                alert.messageText = L10n.text(additional ? "此密钥正被会话引用，仍要删除？" : "删除应用内密钥？")
                alert.informativeText = key.name + "\n" + L10n.text(additional
                    ? "以下会话引用此密钥，删除后可能无法登录。会话配置不会自动修改。"
                    : "使用此路径的会话将无法再用该密钥认证，原始文件不受影响。")
                if !affected.isEmpty {
                    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 180))
                    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false
                    let view = NSTextView(frame: scroll.bounds)
                    view.isEditable = false; view.isSelectable = true
                    view.isVerticallyResizable = true; view.isHorizontallyResizable = false
                    view.textContainer?.widthTracksTextView = true
                    view.string = affected.joined(separator: "\n")
                    scroll.documentView = view; alert.accessoryView = scroll
                }
                alert.alertStyle = additional ? .warning : .informational
                alert.addButton(withTitle: L10n.text("取消"))
                alert.addButton(withTitle: L10n.text(additional ? "仍然删除密钥" : "删除"))
                return alert.runModal() == .alertSecondButtonReturn
            }
        } catch { message = error.localizedDescription }
    }
}
struct SSHKeySettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject var state = SSHKeySettingsState()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH 密钥管理").font(.title2.bold()); Spacer()
                Button("导入私钥…", action: state.importKey)
                Button("刷新", action: state.refresh)
            }
            Text("支持 ssh-keygen 的 OpenSSH / PEM 私钥，包括有口令的密钥。按原格式复制，口令仍在连接时输入；同名 .pub 文件会一并导入。也可在 SSH 配置中直接选用 ~/.ssh 的原文件。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("关联信息包含应用中的服务器、保存的会话、已打开标签和跳板机；不包含外部程序或 SSH 配置文件隐式引用。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(state.keys) { key in
                VStack(alignment: .leading) {
                    Text(key.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(key.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("关联会话").font(.caption.bold())
                    if let matches = state.associations[key.id], !matches.isEmpty {
                        Text(matches.joined(separator: "\n")).font(.caption).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("未发现应用内显式引用").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("查看公钥") { state.showPublic(key) }
                        Button("删除", role: .destructive) { state.delete(key) }
                    }
                }.padding(.vertical, 4)
            }
            if state.keys.isEmpty { Text("暂无导入的密钥").foregroundStyle(.secondary) }
            Text(L10n.text(state.message)).font(.caption)
        }.padding(24).onAppear(perform: state.refresh)
            .onChange(of: interfaceLanguage.selection) { _, _ in state.refresh() }
    }
}
