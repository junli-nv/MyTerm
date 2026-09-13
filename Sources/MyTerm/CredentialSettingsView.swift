import SwiftUI
import MyTermCore

struct CredentialSessionReference {
    let server: Server
    let label: String
}

final class CredentialSettingsState: ObservableObject {
    @Published var message = ""
    @Published var entries: [StoredPasswordInfo] = []
    @Published var associations: [String: [String]] = [:]
    @Published private(set) var revealed: [String: String] = [:]
    @Published var loading = false
    private let store: SQLitePasswordStore
    private var generation = UUID()
    init(store: SQLitePasswordStore = SQLitePasswordStore()) { self.store = store }

    static func matching(_ entries: [StoredPasswordInfo], references: [CredentialSessionReference]) -> [String: [String]] {
        var scopes: [String: Set<String>] = [:]
        for reference in references {
            var variants = [reference.server]
            if let resolved = try? SSHConfigurationResolver.resolvingJump(reference.server), resolved != reference.server { variants.append(resolved) }
            for server in variants {
                if let scope = try? SSHPasswordMemory.scopeIdentifier(for: server) { scopes[scope, default: []].insert(reference.label) }
            }
        }
        return Dictionary(uniqueKeysWithValues: entries.map { entry in
            let scope = String(entry.id.split(separator: ":", maxSplits: 1).first ?? "")
            return (entry.id, Array(scopes[scope] ?? []).sorted())
        })
    }
    func refresh() {
        hideAll(); message = ""; loading = true
        let token = UUID(); generation = token
        var references: [CredentialSessionReference] = []
        if let workspace = (NSApp.delegate as? AppDelegate)?.workspace {
            references += workspace.servers.map { CredentialSessionReference(server: $0, label: $0.displayName) }
            for saved in workspace.savedSessions {
                references += saved.tabs.compactMap { tab in tab.server.map { CredentialSessionReference(server: $0, label: saved.name + " / " + $0.displayName) } }
            }
            for session in workspace.sessions {
                for server in [session.sourceServer, session.server].compactMap({ $0 }) {
                    references.append(CredentialSessionReference(server: server, label: L10n.text("已打开") + " · " + session.label))
                }
            }
        }
        let candidates = references, store = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let entries = try store.list()
                let matches = Self.matching(entries, references: candidates)
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.entries = entries; self.associations = matches; self.loading = false
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.message = message; self.loading = false
                }
            }
        }
    }
    func hideAll() { revealed.removeAll() }
    func toggleReveal(_ entry: StoredPasswordInfo) {
        if revealed.removeValue(forKey: entry.id) != nil { return }
        do {
            guard let password = try store.read(entry.id) else { message = "密码记录已不存在，请刷新。"; return }
            revealed[entry.id] = password
        } catch { message = error.localizedDescription }
    }
    func rename(_ entry: StoredPasswordInfo, name: String) throws {
        try store.rename(entry.id, name: name)
        entries = try store.list()
    }
    func promptRename(_ entry: StoredPasswordInfo) {
        let alert = NSAlert(); alert.messageText = L10n.text("设置密码名称")
        alert.informativeText = L10n.text("最多 120 个字符；留空恢复默认名称，不影响登录配置。")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26)); field.stringValue = entry.name ?? ""
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try rename(entry, name: field.stringValue); message = "密码名称已保存。" }
        catch { message = error.localizedDescription }
    }
    func update(_ entry: StoredPasswordInfo) {
        hideAll()
        let alert = NSAlert(); alert.messageText = L10n.text("更新已保存密码")
        alert.informativeText = entry.displayName + "\n" + L10n.text("仅更新本地记录，不修改服务器密码；下次认证时使用。")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        defer { field.stringValue = "" }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !field.stringValue.isEmpty else { message = "密码不能为空。"; return }
        do { try store.save(field.stringValue, account: entry.id); message = "密码已更新，下次连接生效。" }
        catch { message = error.localizedDescription }
    }
    func delete(_ entry: StoredPasswordInfo) {
        hideAll()
        do { try store.delete(entry.id); refresh(); message = "已删除所选密码。" }
        catch { message = error.localizedDescription }
    }
    func clear() {
        hideAll()
        let alert = NSAlert(); alert.messageText = L10n.text("清除所有已保存的 SSH 密码？")
        alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("清除"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try store.deleteAll(); refresh(); message = "已清除 MyTerm 保存的 SSH 密码。" }
        catch { message = error.localizedDescription }
    }
}
struct CredentialSettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject var state = CredentialSettingsState()
    var automaticallyRefresh = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH 密码管理").font(.title2.bold()); Spacer()
                if state.loading { ProgressView().controlSize(.small) }
                Button("刷新", action: state.refresh).disabled(state.loading)
            }
            Text("可为密码设置名称、查看关联会话，或按需显示当前密码。密码默认隐藏；离开页面或窗口失去焦点后重新隐藏。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(state.entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.displayName).font(.headline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text(entry.label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("关联会话").font(.caption.bold())
                    if let matches = state.associations[entry.id], !matches.isEmpty {
                        Text(matches.joined(separator: "\n")).font(.caption).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("无匹配会话（配置可能已更改或删除）").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        Button("设置名称…") { state.promptRename(entry) }
                        Button(L10n.text(state.revealed[entry.id] == nil ? "查看密码" : "隐藏密码")) { state.toggleReveal(entry) }
                        Button("更新密码…") { state.update(entry) }
                        Button("删除", role: .destructive) { state.delete(entry) }
                    }
                    if let password = state.revealed[entry.id] {
                        ScrollView(.horizontal) {
                            Text(verbatim: password).font(.system(.body, design: .monospaced)).textSelection(.enabled).fixedSize()
                        }.frame(height: 32).privacySensitive()
                    } else { Text("••••••••").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                }.padding(.vertical, 8)
            }
            if state.entries.isEmpty && !state.loading { Text("暂无已保存的密码").foregroundStyle(.secondary) }
            Button("清除所有已记住的 SSH 密码", role: .destructive, action: state.clear)
            Text(L10n.text(state.message)).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.padding(24)
            .onAppear { if automaticallyRefresh { state.refresh() } }
            .onDisappear { state.hideAll() }
            .onChange(of: interfaceLanguage.selection) { _, _ in if automaticallyRefresh { state.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in state.hideAll() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in state.hideAll() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in state.hideAll() }
    }
}
