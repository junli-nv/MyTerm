import SwiftUI
import MyTermCore
import Combine
import UniformTypeIdentifiers

final class Workspace: ObservableObject {
    lazy var codex = CodexBridge(workspace: self, persist: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    @Published var groups: [SessionGroup] = []
    @Published var groupRecoveryRequired = false
    private let groupRepository: SessionGroupRepository
    private var groupsLoadFailed = false
    @Published var sidebarVisible = !UserDefaults.standard.bool(forKey: "layout.sidebarHidden") {
        didSet { if !ProcessInfo.processInfo.arguments.contains("--smoke-test") { UserDefaults.standard.set(!sidebarVisible, forKey: "layout.sidebarHidden") } }
    }
    @Published var historyPresented = false
    let history: HistoryModel
    private var historyTimer: Timer?
    private var historyErrors: AnyCancellable?
    @Published var importPresented = false
    @Published var savedSessions: [SavedSession] = []
    private let sessionRepository: SessionRepository
    private var sessionsLoadFailed = false
    @Published var search = ""
    @Published var servers: [Server] = []
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: UUID?
    @Published var editor: Server?
    @Published var error: String?
    private var loadFailed = false
    private var restoredBackup = false
    private let repository: ServerRepository

    init(applicationSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        let directory = applicationSupportDirectory
        groupRepository = SessionGroupRepository(url: directory.appendingPathComponent("MyTerm/groups.json"))
        history = HistoryModel(directory: directory.appendingPathComponent("MyTerm/History"))
        sessionRepository = SessionRepository(url: directory.appendingPathComponent("MyTerm/sessions.json"))
        repository = ServerRepository(fileURL: directory.appendingPathComponent("MyTerm/servers.json"))
        do { servers = try repository.load() }
        catch {
            loadFailed = true
            self.error = "无法读取服务器配置，原文件已保留：\(error.localizedDescription)"
        }
        do { savedSessions = try sessionRepository.load() }
        catch { sessionsLoadFailed = true; self.error = "无法读取保存的会话：\(error.localizedDescription)" }
        groups = groupRepository.loadForStartup()
        groupRecoveryRequired = (try? groupRepository.load()) == nil
        historyErrors = history.$error.compactMap { $0 }.sink { [weak self] in self?.error = $0 }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            historyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.archiveHistory() }
        }
    }

    var selected: TerminalSession? { sessions.first { $0.id == selectedID } }
    func selectAdjacentTab(_ direction: Int) {
        guard !sessions.isEmpty else { return }
        guard let index = sessions.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = sessions[direction < 0 ? sessions.count - 1 : 0].id
            return
        }
        selectedID = sessions[(index + (direction < 0 ? sessions.count - 1 : 1)) % sessions.count].id
    }
    func backupConfigurationFiles() throws -> [String: Data] {
        guard !loadFailed, !groupsLoadFailed, !sessionsLoadFailed else { throw ConfigurationError.invalid("请先修复配置文件再备份。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var saved = savedSessions
        if !sessions.isEmpty, sessions.count <= 100 {
            saved.append(SavedSession(name: "备份时的会话", tabs: sessions.map { SessionTab(server: $0.sourceServer, directory: $0.sourceServer == nil ? $0.directory : nil, encoding: $0.encoding, historyLogging: $0.historyLogging) }, selectedIndex: sessions.firstIndex(where: { $0.id == selectedID }) ?? 0))
        }
        return ["servers.json": try encoder.encode(servers), "groups.json": try encoder.encode(groups), "sessions.json": try encoder.encode(saved)]
    }
    func acceptRestoredConfiguration(servers: [Server], groups: [SessionGroup], saved: [SavedSession]) {
        self.sessions = []; selectedID = nil
        self.servers = servers; self.groups = groups; savedSessions = saved
        loadFailed = false; groupsLoadFailed = false; groupRecoveryRequired = false; sessionsLoadFailed = false; restoredBackup = true
    }

    private var configurationArchive: SessionArchive {
        SessionArchive(servers: servers, groups: groups, sessions: savedSessions)
    }

    func exportSessions() {
        guard !loadFailed, !groupsLoadFailed, !sessionsLoadFailed else {
            error = "配置读取失败，请修复后再导出。"; return
        }
        let panel = NSSavePanel()
        panel.title = L10n.text("导出会话配置")
        panel.nameFieldStringValue = "MyTerm-sessions.json"
        panel.allowedContentTypes = [.json]
        panel.message = "包含服务器、分组和已保存的多标签会话。当前标签请先保存；密码、私钥和历史文本不包含在内。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try configurationArchive.encoded().write(to: url, options: .atomic) }
        catch { self.error = "导出失败：\(error.localizedDescription)" }
    }

    func exportOpenSSH() {
        guard !loadFailed, !servers.isEmpty else { error = "没有可导出的服务器配置。"; return }
        let panel = NSSavePanel(); panel.title = L10n.text("导出 OpenSSH 配置")
        panel.nameFieldStringValue = "myterm_ssh_config"
        panel.message = "导出侧栏服务器。引用现有 ~/.ssh/config、密钥路径及代理辅助程序；请保存为独立文件，使用 ssh -F 指定。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let original = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard url.resolvingSymlinksInPath().standardizedFileURL != original.resolvingSymlinksInPath().standardizedFileURL else {
            error = "请另存为独立文件，避免覆盖被引用的 ~/.ssh/config。"; return
        }
        let values = servers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let resolved = try values.map { try SSHConfigurationResolver.resolvingJump($0) }
                try Data(OpenSSHExport.render(resolved).utf8).write(to: url, options: .atomic)
            } catch { DispatchQueue.main.async { self?.error = "导出失败：\(error.localizedDescription)" } }
        }
    }

    func importSessions() {
        guard !loadFailed, !groupsLoadFailed, !sessionsLoadFailed else {
            error = "配置读取失败，请修复后再导入，以免覆盖原文件。"; return
        }
        let panel = NSOpenPanel()
        panel.title = L10n.text("导入会话配置"); panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "导入 MyTerm 导出的 JSON 文件。相同记录跳过，冲突时取消整次导入；不会自动连接。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw ConfigurationError.invalid("会话文件不能超过 20 MB。") }
            let incoming = try SessionArchive.decode(Data(contentsOf: url))
            let merged = try configurationArchive.merging(incoming)
            let addedServers = merged.servers.count - servers.count
            let addedSessions = merged.sessions.count - savedSessions.count
            let addedGroups = merged.groups.count - groups.count
            // Keep exact original bytes for rollback if any repository write fails.
            let urls = [repository.fileURL, groupRepository.url, sessionRepository.url]
            let originals: [Data?] = try urls.map { FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil }
            do {
                try repository.save(merged.servers)
                try groupRepository.save(merged.groups)
                try sessionRepository.save(merged.sessions)
            } catch {
                let writeError = error
                do {
                    for (path, bytes) in zip(urls, originals) {
                        if let bytes { try bytes.write(to: path, options: .atomic) }
                        else if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
                    }
                } catch {
                    loadFailed = true; groupsLoadFailed = true; sessionsLoadFailed = true
                    throw ConfigurationError.invalid("导入写入失败且回滚失败，请检查配置文件后重启：\(error.localizedDescription)")
                }
                throw writeError
            }
            servers = merged.servers; groups = merged.groups; groupRecoveryRequired = false; savedSessions = merged.sessions
            let alert = NSAlert(); alert.messageText = L10n.text("导入完成")
            alert.informativeText = "新增 \(addedServers) 个服务器、\(addedGroups) 个分组、\(addedSessions) 个保存会话。相同记录已跳过。"
            alert.runModal()
        } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }

    @discardableResult
    private func saveGroups(_ updated: [SessionGroup]) -> Bool {
        guard !groupRecoveryRequired else { return false }
        guard !groupsLoadFailed else { error = "请先修复 groups.json 并重启，以免覆盖原分组。"; return false }
        do { try groupRepository.save(updated); groups = updated; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func editGroup(_ group: SessionGroup? = nil) {
        guard !groupRecoveryRequired else { return }
        guard !groupsLoadFailed else { error = "请先修复 groups.json 并重启，以免覆盖原分组。"; return }
        GroupNameDialog(name: group?.name).run { name in
            var updated = groups
            if let group, let index = updated.firstIndex(where: { $0.id == group.id }) { updated[index].name = name }
            else { updated.append(SessionGroup(name: name)) }
            try groupRepository.save(updated)
            groups = updated
        }
    }
    /// A drag onto an ungrouped peer creates one group atomically, after naming it.
    /// Revalidate when saving because a modal dialog can process other UI events.
    func canGroupServers(_ source: UUID, with target: UUID) -> Bool {
        source != target && [source, target].allSatisfy { id in
            servers.contains { $0.id == id } && !groups.contains { $0.serverIDs.contains(id) }
        }
    }
    func createGroupFromServers(_ source: UUID, target: UUID, name: String) throws {
        guard !groupRecoveryRequired, !groupsLoadFailed, canGroupServers(source, with: target) else {
            throw ConfigurationError.invalid("会话已移动或删除，请取消后重新拖拽。")
        }
        let updated = groups + [SessionGroup(name: SessionGroup.normalizedName(name), serverIDs: [target, source])]
        try groupRepository.save(updated)
        groups = updated
    }
    @discardableResult
    func promptGroupFromServers(_ source: UUID, target: UUID) -> Bool {
        guard !groupRecoveryRequired, !groupsLoadFailed, canGroupServers(source, with: target) else { return false }
        let dialog = GroupNameDialog(name: nil)
        let names = [target, source].compactMap { id in servers.first { $0.id == id }?.displayName }
        dialog.alert.informativeText = L10n.text("创建分组后将加入以下两个会话；取消不会更改分组。") + "\n" + names.joined(separator: "\n")
        var saved = false
        dialog.run { name in
            try createGroupFromServers(source, target: target, name: name)
            saved = true
        }
        return saved
    }
    func moveServer(_ server: Server, to group: UUID?) {
        do { saveGroups(try SessionGroupRepository.moving(server.id, to: group, in: groups)) }
        catch { self.error = error.localizedDescription }
    }
    func repairGroupFile() {
        do {
            try groupRepository.save(groups)
            groupRecoveryRequired = false
        } catch { self.error = error.localizedDescription }
    }
    func removeGroupFile() {
        do {
            try groupRepository.removePreservingOriginal()
            groups = []; groupRecoveryRequired = false
        } catch { self.error = error.localizedDescription }
    }
    func moveDraggedServers(_ ids: [UUID], to group: UUID?) -> Bool {
        guard !ids.isEmpty, ids.allSatisfy({ id in servers.contains { $0.id == id } }),
              group == nil || groups.contains(where: { $0.id == group }) else { return false }
        do {
            var updated = groups
            for id in Set(ids) { updated = try SessionGroupRepository.moving(id, to: group, in: updated) }
            return saveGroups(updated)
        } catch { self.error = error.localizedDescription; return false }
    }
    func deleteGroup(_ group: SessionGroup) { saveGroups(groups.filter { $0.id != group.id }) }
    func toggleGroup(_ group: SessionGroup) {
        var updated = groups
        guard let index = updated.firstIndex(where: { $0.id == group.id }) else { return }
        updated[index].collapsed.toggle(); saveGroups(updated)
    }

    @discardableResult
    func openCodex(executable: String, arguments: [String], environment: [String: String], proxy: CodexSOCKSProxy? = nil, executionBridge: CodexBridge? = nil, targetSessionID: UUID? = nil, onExit: ((Int32?) -> Void)? = nil) -> TerminalSession {
        let session = TerminalSession(label: "Codex", executable: executable, arguments: arguments, launchEnvironment: environment, launchProxy: proxy, retainOnExit: true)
        session.codexExecutionBridge = executionBridge; session.codexTargetSessionID = targetSessionID
        session.onProcessExit = onExit
        add(session)
        return session
    }

    func newLocal(directory: String? = nil) {
        let args = ProcessInfo.processInfo.arguments.contains("--smoke-test")
            ? ["--noprofile", "--norc", "-i"] : ["--login"]
        add(TerminalSession(label: "本地 Bash", executable: "/bin/bash", arguments: args, directory: directory))
    }

    func connect(_ server: Server) {
        do {
            let server = try server.validated()
            add(TerminalSession(label: server.displayName, executable: "/usr/bin/ssh", arguments: [], server: server))
        } catch { self.error = error.localizedDescription }
    }

    func duplicate(_ session: TerminalSession) {
        if let server = session.sourceServer { connect(server) }
        else { newLocal(directory: session.directory) }
        if selectedID != session.id, let selected {
            selected.encoding = session.encoding
            setHistoryLogging(session.historyLogging, for: selected)
        }
    }

    func renameTab(_ session: TerminalSession) {
        selectedID = session.id
        let alert = NSAlert(); alert.messageText = L10n.text("更改标签名称")
        let field = NSTextField(string: session.label)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请输入标签名称。"; return }
        objectWillChange.send(); session.label = name
    }

    func editConnection(_ session: TerminalSession) {
        guard let server = session.sourceServer else { return }
        selectedID = session.id
        editor = servers.first(where: { $0.id == server.id }) ?? server
    }

    func setHistoryLogging(_ mode: HistoryLoggingMode, for session: TerminalSession) {
        session.historyLogging = mode
        history.setLoggingMode(mode, for: session.id)
    }

    private func add(_ session: TerminalSession) {
        history.setLoggingMode(session.historyLogging, for: session.id)
        session.onNormalExit = { [weak self, weak session] in
            guard let self, let session else { return }; self.close(session)
        }
        sessions.append(session)
        selectedID = session.id
    }

    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        archiveHistory([session])
        history.forgetSession(session.id)
        session.stop()
        sessions.remove(at: index)
        if selectedID == session.id {
            selectedID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id
        }
    }

    func save(_ server: Server) -> Bool {
        guard !loadFailed else {
            error = "请先修复 ~/Library/Application Support/MyTerm/servers.json 并重启，以免覆盖无法读取的配置。"
            return false
        }
        do {
            let server = try server.validated()
            var updated = servers
            if let index = updated.firstIndex(where: { $0.id == server.id }) { updated[index] = server }
            else { updated.append(server) }
            try repository.save(updated)
            servers = updated
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ server: Server) {
        guard !loadFailed else { return }
        let updated = servers.filter { $0.id != server.id }
        do { try repository.save(updated); servers = updated }
        catch { self.error = error.localizedDescription }
    }

    func importServers(_ imported: [Server]) -> Bool {
        guard !loadFailed else { error = "请先修复服务器配置文件。"; return false }
        do {
            var updated = servers
            for server in imported where !updated.contains(where: { $0.host == server.host }) { updated.append(try server.validated()) }
            try repository.save(updated); servers = updated; return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func saveSession() {
        guard !sessions.isEmpty, !sessionsLoadFailed else { error = "没有可保存的标签，或会话配置无法读取。"; return }
        let alert = NSAlert(); alert.messageText = L10n.text("保存当前会话"); alert.informativeText = L10n.text("保存标签顺序和连接配置，恢复时重新连接。密码和终端进程不会被保存。")
        let field = NSTextField(string: "工作会话"); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请输入会话名称。"; return }
        persistSession(named: name)
    }

    private func persistSession(named name: String, replaceLast: Bool = false) {
        guard !sessionsLoadFailed, !sessions.isEmpty else { return }
        guard sessions.count <= 100 else { error = "每个保存的会话最多包含 100 个标签。"; return }
        let item = SavedSession(name: name, tabs: sessions.map { SessionTab(server: $0.server, directory: $0.server == nil ? $0.directory : nil, encoding: $0.encoding, historyLogging: $0.historyLogging) },
            selectedIndex: sessions.firstIndex(where: { $0.id == selectedID }) ?? 0)
        var updated = savedSessions
        if replaceLast { updated.removeAll { $0.name == "上次退出时的会话" } }
        updated.append(item)
        do { try sessionRepository.save(updated); savedSessions = updated }
        catch { self.error = error.localizedDescription }
    }

    func saveOnExit() {
        guard !restoredBackup else { return }
        guard !ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
        archiveHistory(wait: true)
        persistSession(named: "上次退出时的会话", replaceLast: true)
    }

    func restore(_ saved: SavedSession) {
        // Append restored tabs so current work is never discarded.
        let start = sessions.count
        for tab in saved.tabs {
            let previousCount = sessions.count
            if let server = tab.server { connect(server) }
            else {
                let directory = tab.directory.flatMap { path -> String? in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : nil
                }
                newLocal(directory: directory)
            }
            if sessions.count > previousCount, let selected {
                selected.encoding = tab.encoding ?? .utf8
                setHistoryLogging(tab.historyLogging ?? selected.historyLogging, for: selected)
            }
        }
        if sessions.indices.contains(start + saved.selectedIndex) { selectedID = sessions[start + saved.selectedIndex].id }
    }
    func deleteSaved(_ saved: SavedSession) {
        let updated = savedSessions.filter { $0.id != saved.id }
        do { try sessionRepository.save(updated); savedSessions = updated }
        catch { self.error = error.localizedDescription }
    }

    func renameSaved(_ saved: SavedSession) {
        guard !sessionsLoadFailed else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("重命名会话")
        let field = NSTextField(string: saved.name); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("保存")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请输入会话名称。"; return }
        var updated = savedSessions
        guard let index = updated.firstIndex(where: { $0.id == saved.id }) else { return }
        updated[index].name = name
        do { try sessionRepository.save(updated); savedSessions = updated }
        catch { self.error = error.localizedDescription }
    }

    func updateSaved(_ saved: SavedSession) {
        guard !sessionsLoadFailed, !sessions.isEmpty, sessions.count <= 100 else {
            error = "当前需要有 1–100 个标签才能更新保存的会话。"; return
        }
        var updated = savedSessions
        guard let index = updated.firstIndex(where: { $0.id == saved.id }) else { return }
        updated[index].tabs = sessions.map { SessionTab(server: $0.server, directory: $0.server == nil ? $0.directory : nil, encoding: $0.encoding, historyLogging: $0.historyLogging) }
        updated[index].selectedIndex = sessions.firstIndex(where: { $0.id == selectedID }) ?? 0
        do { try sessionRepository.save(updated); savedSessions = updated }
        catch { self.error = error.localizedDescription }
    }

    func stopAll() { sessions.forEach { $0.stop() } }

    func archiveHistory(_ tabs: [TerminalSession]? = nil, wait: Bool = false) {
        guard !ProcessInfo.processInfo.arguments.contains("--smoke-test"), wait || !history.saving else { return }
        let candidates = tabs ?? sessions
        for session in candidates { history.setLoggingMode(session.historyLogging, for: session.id) }
        history.save(candidates.filter { $0.historyLogging.resolves(global: HistoryPreferences.shared.policy.enabled) }.map { $0.historySnapshot() }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, wait: wait)
    }
    func showHistory() {
        archiveHistory(); history.refresh(select: selectedID); historyPresented = true
    }
    func exportHistory() {
        guard let selected else { return }
        history.export(text: selected.historySnapshot().text, label: selected.label)
    }
}
