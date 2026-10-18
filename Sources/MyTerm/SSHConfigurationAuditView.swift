import AppKit
import SwiftUI
import MyTermCore

final class SSHConfigurationAuditModel: ObservableObject {
    @Published var rows: [SSHConfigurationAudit.Row] = []
    @Published var unusedPasswords: [String] = []
    @Published var unusedKeys: [String] = []
    @Published var dependencies: [String] = []
    @Published var message = ""
    @Published var loading = false
    private(set) var exportServers: [Server] = []
    private var generation = UUID()
    func refresh(workspace: Workspace) {
        loading = true; message = ""
        let token = UUID(); generation = token
        exportServers = workspace.servers
        dependencies = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config").path, "/etc/ssh/ssh_config"]
        dependencies += workspace.servers.filter { $0.proxy != nil }.compactMap { try? $0.proxy?.command() }
        dependencies = Array(Set(dependencies)).sorted()
        var references = workspace.servers.map { SSHConfigurationAudit.Reference(server: $0, source: L10n.text("当前会话") + " · " + $0.displayName, exported: true) }
        for saved in workspace.savedSessions {
            for tab in saved.tabs {
                if let server = tab.server { references.append(.init(server: server, source: L10n.text("保存的快照") + " · " + saved.name + " / " + server.displayName, exported: false)) }
            }
        }
        for session in workspace.sessions {
            if let server = session.server ?? session.sourceServer { references.append(.init(server: server, source: L10n.text("已打开") + " · " + session.label, exported: false)) }
        }
        let libraryKeyPaths = workspace.jumpProfiles.map(\.identityFile)
        let captured = references
        let store = workspace.auditCredentialStore
        let library = workspace.auditKeyLibrary
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = try? store.list()
            let keys = try? library.list()
            let result = SSHConfigurationAudit.inspect(captured, passwordAccounts: entries.map { Set($0.map(\.id)) })
            RunLoop.main.perform {
                guard let self, self.generation == token else { return }
                self.rows = result.rows
                self.unusedPasswords = (entries ?? []).filter { result.unusedPasswordAccounts.contains($0.id) }.map(\.displayName)
                func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
                let configuredPaths = libraryKeyPaths + captured.flatMap { ref in [ref.server.identityFile] + (ref.server.jumpServers ?? []).map(\.identityFile) }
                let referencedPaths = Set(configuredPaths.filter { !$0.isEmpty }.map { canonical(($0 as NSString).expandingTildeInPath) })
                self.unusedKeys = (keys ?? []).filter { !referencedPaths.contains(canonical($0.url.path)) }.map(\.name)
                self.message = [entries == nil ? L10n.text("无法读取密码元数据，密码状态未知。") : nil,
                                keys == nil ? L10n.text("无法读取托管密钥列表，未关联密钥检查不可用。") : nil].compactMap { $0 }.joined(separator: "\n")
                self.loading = false
            }
        }
    }
}

final class SSHConfigurationAuditWindow {
    private var window: NSWindow?
    func show(workspace: Workspace, export: @escaping ([Server]) -> Void) {
        window?.close()
        let model = SSHConfigurationAuditModel()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 650), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 620, height: 420)
        panel.title = L10n.text("SSH 配置检查与导出")
        let hosting = NSHostingView(rootView: SSHConfigurationAuditView(model: model, refresh: { [weak workspace] in
            if let workspace { model.refresh(workspace: workspace) }
        }, finish: { export(model.exportServers) }))
        // The window owns its size; a long lazy report must not raise its minimum height.
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
        model.refresh(workspace: workspace)
    }
}

struct SSHConfigurationAuditView: View {
    @ObservedObject var model: SSHConfigurationAuditModel
    @ObservedObject var language = LanguagePreferences.shared
    let refresh: () -> Void
    let finish: () -> Void
    private func password(_ value: SSHConfigurationAudit.PasswordStatus) -> String {
        switch value {
        case .saved: return L10n.text("已保存密码（未验证有效性）")
        case .absent: return L10n.text("未保存密码，连接时可能询问")
        case .unspecifiedUser: return L10n.text("用户名由外部配置决定，凭据无法确认")
        case .notUsed: return L10n.text("密钥模式，不使用密码")
        case .unavailable: return L10n.text("密码状态未知")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSH 配置检查与导出").font(.title2.bold())
            Text("仅检查配置和凭据元数据，不读取密码或私钥正文、不连接服务器。导出只包含当前侧栏会话及其跳板；快照和已打开标签仅用于追踪引用。")
                .fixedSize(horizontal: false, vertical: true)
            Text("外部 SSH 配置、Include、默认密钥和 SSH agent 未展开验证；文件存在及密码已保存不代表能成功登录。OpenSSH 文件不包含密码。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.host + " · " + (row.user.isEmpty ? "?" : row.user) + ":" + (row.port.isEmpty ? L10n.text("SSH 配置默认端口") : row.port)).font(.headline)
                            Text(row.source + " · " + (row.hop.map { L10n.text("跳板机") + " \($0)" } ?? L10n.text("目标服务器")))
                            Text(L10n.text(row.exported ? "包含在本次 OpenSSH 导出中" : "仅作为引用记录，不包含在本次导出中")).foregroundStyle(.secondary)
                            Text(password(row.password))
                            if let available = row.keyAvailable {
                                Text((available ? L10n.text("密钥文件存在且可读：") : L10n.text("密钥文件缺失或不可读：")) + row.keyPath)
                                    .foregroundStyle(available ? Color.secondary : .orange)
                            }
                            if let jump = row.externalJump { Text(L10n.text("外部跳板定义（未解析）：") + jump) }
                            if let profile = row.profileID { Text(L10n.text("公共跳板 ID：") + profile.uuidString).font(.caption) }
                        }.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                    Text("导出引用的外部配置及代理命令（未执行）").font(.headline)
                    ForEach(model.dependencies, id: \.self) { Text($0).textSelection(.enabled) }
                    if !model.unusedKeys.isEmpty {
                        Text("未关联已知配置的托管密钥").font(.headline)
                        Text("以下记录可能仍被外部配置使用，不会自动删除。")
                        ForEach(model.unusedKeys, id: \.self) { Text($0) }
                    }
                    if !model.unusedPasswords.isEmpty {
                        Text("未关联已知会话的已保存密码").font(.headline)
                        Text("以下记录可能仍被外部配置使用，不会自动删除。")
                        ForEach(Array(model.unusedPasswords.enumerated()), id: \.offset) { _, label in Text(label) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.visible)
            HStack {
                Button("刷新", action: refresh).disabled(model.loading)
                if model.loading { ProgressView().controlSize(.small) }
                Spacer()
                Button("导出 OpenSSH 配置…", action: finish).disabled(model.loading || model.exportServers.isEmpty)
            }
        }.padding(20).environment(\.locale, language.locale)
            .onChange(of: language.selection) { _, _ in refresh() }
    }
}
