import AppKit
import SwiftUI
import MyTermCore

extension Workspace {
    /// Include snapshots and active transports when deciding whether deletion is safe.
    func jumpLibraryReferences(_ id: UUID) -> [String] {
        var names = jumpReferences(id)
        for saved in savedSessions where saved.tabs.contains(where: { ($0.server?.jumpServers ?? []).contains { $0.profileID == id } }) {
            names.append(L10n.text("保存的快照") + " · " + saved.name)
        }
        for session in sessions where ((session.server ?? session.sourceServer)?.jumpServers ?? []).contains(where: { $0.profileID == id }) {
            names.append(L10n.text("已打开") + " · " + session.label)
        }
        return Array(Set(names)).sorted()
    }
    func saveJumpProfile(_ original: SSHJumpServer) throws {
        guard !loadFailed else { throw ConfigurationError.invalid("配置读取失败，请修复后再保存。") }
        var profile = try original.validated(); profile.profileID = profile.id
        var catalog = jumpProfiles.filter { $0.id != profile.id }; catalog.append(profile)
        let updated = servers.map { original -> Server in
            var server = original
            server.jumpServers = server.jumpServers?.map { hop in
                guard hop.profileID == profile.id else { return hop }
                var replacement = profile; replacement.id = hop.id; return replacement
            }
            return server
        }
        try repository.save(updated, profiles: catalog)
        servers = updated; jumpProfiles = catalog
        for session in sessions { session.updateSharedJumps(from: servers, profiles: jumpProfiles) }
    }
    func deleteJumpProfile(_ id: UUID) throws {
        guard !loadFailed else { throw ConfigurationError.invalid("配置读取失败，请修复后再保存。") }
        guard jumpLibraryReferences(id).isEmpty else { throw ConfigurationError.invalid("此跳板机仍被引用，请先在相关会话或快照中移除引用。") }
        let catalog = jumpProfiles.filter { $0.id != id }
        try repository.save(servers, profiles: catalog)
        jumpProfiles = catalog
    }
}

final class JumpManagerDraft: ObservableObject {
    @Published var search = ""
    @Published var profile = SSHJumpServer()
    @Published var editing = false
    @Published var route = "direct"
    @Published var error = ""
    func select(_ value: SSHJumpServer) { profile = value; editing = true; error = ""; route = "direct" }
}

struct SharedJumpManagerView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var language = LanguagePreferences.shared
    @StateObject private var draft: JumpManagerDraft
    @StateObject private var test: JumpConnectionTest
    init(workspace: Workspace, draft: JumpManagerDraft = JumpManagerDraft(), test: JumpConnectionTest = JumpConnectionTest()) {
        self.workspace = workspace; _draft = StateObject(wrappedValue: draft); _test = StateObject(wrappedValue: test)
    }
    private struct RouteChoice: Identifiable { let id: String; let title: String; let server: Server; let index: Int }
    private var routes: [RouteChoice] {
        workspace.servers.flatMap { server in
            (server.jumpServers ?? []).enumerated().compactMap { index, hop in
                guard hop.profileID == draft.profile.id else { return nil }
                return RouteChoice(id: server.id.uuidString + ":" + String(index), title: server.displayName + " · " + String(index + 1), server: server, index: index)
            }
        }
    }
    private func testConnection() {
        do {
            if draft.route == "direct" { test.start(try SSHJumpProbe(profile: draft.profile)) }
            else if let route = routes.first(where: { $0.id == draft.route }) {
                test.start(try SSHJumpProbe(profile: draft.profile, via: route.server, index: route.index))
            } else { throw ConfigurationError.invalid("测试路径已变化，请重新选择。") }
        } catch { draft.error = L10n.text(error.localizedDescription) }
    }
    private var matches: [SSHJumpServer] {
        workspace.sharedJumpProfiles.filter { profile in
            draft.search.isEmpty || ([profile.editableName, profile.host, profile.user, profile.port] + workspace.jumpLibraryReferences(profile.id)).joined(separator: " ").localizedCaseInsensitiveContains(draft.search)
        }
    }
    private func save() {
        do {
            let profile = try draft.profile.validated()
            if let old = workspace.jumpProfiles.first(where: { $0.id == profile.id }), !SharedSSHJumps.sameDefinition(old, profile) {
                let refs = workspace.jumpLibraryReferences(profile.id)
                if !refs.isEmpty {
                    let alert = NSAlert(); alert.messageText = L10n.text("更新跳板机配置？")
                    alert.informativeText = L10n.text("以下会话将在下次连接时使用新配置，已连接的会话不会中断：") + "\n" + refs.joined(separator: "\n")
                    alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
            }
            try workspace.saveJumpProfile(profile); draft.editing = false; draft.error = ""
        } catch { draft.error = L10n.text(error.localizedDescription) }
    }
    private func delete() {
        let alert = NSAlert(); alert.messageText = L10n.text("删除跳板机配置？")
        alert.informativeText = SSHJumpCredentials.label(draft.profile)
        alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("删除"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try workspace.deleteJumpProfile(draft.profile.id); draft.editing = false; draft.error = "" }
        catch { draft.error = L10n.text(error.localizedDescription) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("跳板机管理").font(.title2.bold())
            Text("管理全部跳板机，包括未使用、单会话使用和多会话共用的配置。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(L10n.text("搜索名称、地址、用户名或引用会话"), text: $draft.search)
                Button("新增") { draft.select(SSHJumpServer()) }.disabled(test.running)
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(matches) { profile in
                            Button { draft.select(profile) } label: {
                                VStack(alignment: .leading) {
                                    Text(profile.displayName).font(.headline)
                                    if !profile.editableName.isEmpty { Text(profile.host).font(.caption) }
                                    Text(profile.user + " : " + profile.port).font(.caption)
                                    Text(L10n.text(profile.authentication == .key ? "密钥" : profile.authentication == .password ? "密码" : "自动")).font(.caption)
                                    Text(L10n.text("引用数量：") + String(workspace.jumpLibraryReferences(profile.id).count)).font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(draft.editing && draft.profile.id == profile.id ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).disabled(test.running)
                        }
                    }
                }.frame(width: 230).scrollIndicators(.visible)
                Divider()
                if draft.editing {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                EditorTextField(title: "名称", text: $draft.profile.editableName, prompt: "留空使用主机地址")
                                EditorTextField(title: "跳板机地址", text: $draft.profile.host, prompt: "IP 或域名")
                                EditorTextField(title: "端口", text: $draft.profile.port, prompt: "22")
                                EditorTextField(title: "用户名", text: $draft.profile.user)
                                Picker("认证方式", selection: $draft.profile.authentication) {
                                    Text("自动").tag(AuthenticationMode.automatic)
                                    Text("密码").tag(AuthenticationMode.password)
                                    Text("密钥").tag(AuthenticationMode.key)
                                }
                                if draft.profile.authentication != .password {
                                    EditorTextField(title: "私钥文件", text: $draft.profile.identityFile)
                                    Button("选择…") {
                                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url { draft.profile.identityFile = url.path }
                                    }
                                }
                                Text("密码在 SSH 会话配置或连接时填写，沿用现有加密凭据管理。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("测试路径", selection: $draft.route) {
                                    Text("直接连接（无前级跳板或代理）").tag("direct")
                                    ForEach(routes) { route in Text(route.title).tag(route.id) }
                                }.disabled(test.running)
                                Text("测试只验证 SSH 连接与认证，不执行远端命令，兼容 Windows 和受限跳板机。成功不保证转发策略或后续目标可达。")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("测试连接", action: testConnection).disabled(test.running)
                                    if test.running { ProgressView().controlSize(.small); Button("取消测试") { test.cancel() } }
                                }
                                if !test.result.isEmpty { Text(test.result).textSelection(.enabled).font(.caption) }
                                Divider()
                                Text("引用会话").font(.headline)
                                let refs = workspace.jumpLibraryReferences(draft.profile.id)
                                if refs.isEmpty { Text("尚未被任何会话引用") }
                                ForEach(refs, id: \.self) { Text($0) }
                                if !refs.isEmpty { Text("删除前请先解除所有引用。").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.scrollIndicators(.visible)
                        HStack {
                            Button("删除", role: .destructive, action: delete)
                                .disabled(!workspace.jumpProfiles.contains { $0.id == draft.profile.id } || !workspace.jumpLibraryReferences(draft.profile.id).isEmpty)
                            Spacer()
                            Button("取消") { draft.editing = false; draft.error = "" }
                            Button("保存", action: save).disabled(test.running)
                        }
                    }
                } else {
                    Text("选择跳板机进行编辑，或点击新增。").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !draft.error.isEmpty { Text(draft.error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.padding(20).environment(\.locale, language.locale)
            .onDisappear { test.cancel() }
            .onChange(of: draft.profile) { _, _ in test.reset() }
            .onChange(of: draft.route) { _, _ in test.reset() }
    }
}
