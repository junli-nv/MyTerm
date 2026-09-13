import AppKit
import MyTermCore

enum PreferencesBackupController {
    private static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyTerm") }
    private static func password(confirm: Bool) -> String? {
        let alert = NSAlert(); alert.messageText = L10n.text(confirm ? "设置备份口令" : "输入备份口令")
        alert.informativeText = L10n.text("备份包含密码和私钥。请妥善保管口令，遗失后无法恢复。")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 34 : 0, width: 360, height: 24))
        field.placeholderString = L10n.text("备份口令")
        let repeated = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24)); repeated.placeholderString = L10n.text("再次输入口令")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: confirm ? 62 : 28)); view.addSubview(field)
        if confirm { view.addSubview(repeated) }
        alert.accessoryView = view; alert.addButton(withTitle: L10n.text("继续")); alert.addButton(withTitle: L10n.text("取消"))
        alert.window.initialFirstResponder = field
        defer { field.stringValue = ""; repeated.stringValue = "" }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard !field.stringValue.isEmpty, !confirm || field.stringValue == repeated.stringValue else {
            let error = NSAlert(); error.messageText = L10n.text("口令不能为空，且两次输入必须一致。"); error.runModal(); return nil
        }
        return field.stringValue
    }
    static func export(workspace: Workspace) {
        let panel = NSSavePanel(); panel.title = L10n.text("导出偏好设置备份")
        panel.nameFieldStringValue = "MyTerm-backup.mytermbackup"
        guard panel.runModal() == .OK, let url = panel.url, let passphrase = password(confirm: true) else { return }
        do {
            var files = try workspace.backupConfigurationFiles()
            files.merge(try SQLitePasswordStore().backupFiles()) { _, new in new }
            for key in try SSHKeyLibrary().list() {
                files["Keys/" + key.name] = try Data(contentsOf: key.url)
                let pub = URL(fileURLWithPath: key.url.path + ".pub")
                if FileManager.default.fileExists(atPath: pub.path) { files["Keys/" + key.name + ".pub"] = try Data(contentsOf: pub) }
            }
            var preferences: [String: Any] = [:]
            for key in PreferencesBackup.preferenceKeys { preferences[key] = UserDefaults.standard.object(forKey: key) }
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
            let backup = PreferencesBackup(files: files, preferences: data)
            try backup.encrypted(passphrase: passphrase).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { workspace.error = error.localizedDescription }
    }
    static func restore(workspace: Workspace) {
        let panel = NSOpenPanel(); panel.title = L10n.text("恢复偏好设置备份"); panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let passphrase = password(confirm: false) else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 90 * 1024 * 1024 else { throw ConfigurationError.invalid("备份文件过大。") }
            let backup = try PreferencesBackup.decrypt(Data(contentsOf: url), passphrase: passphrase)
            let fm = FileManager.default
            let stage = root.appendingPathComponent(".restore-\(UUID())")
            let previous = root.appendingPathComponent(".previous-\(UUID())")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: stage) }
            for (path, bytes) in backup.files {
                let target = stage.appendingPathComponent(path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try bytes.write(to: target)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
            var scopes: [String: String] = [:]
            func relocated(_ server: Server) throws -> Server {
                var result = server
                let name = URL(fileURLWithPath: server.identityFile).lastPathComponent
                if server.identityFile.contains("/MyTerm/Keys/"), backup.files["Keys/" + name] != nil {
                    result.identityFile = root.appendingPathComponent("Keys/" + name).path
                }
                if var hops = result.jumpServers {
                    for index in hops.indices {
                        let name = URL(fileURLWithPath: hops[index].identityFile).lastPathComponent
                        if hops[index].identityFile.contains("/MyTerm/Keys/"), backup.files["Keys/" + name] != nil {
                            hops[index].identityFile = root.appendingPathComponent("Keys/" + name).path
                        }
                    }
                    result.jumpServers = hops
                }
                if result != server { scopes[try SSHPasswordMemory.scopeIdentifier(for: server)] = try SSHPasswordMemory.scopeIdentifier(for: result) }
                return result
            }
            let servers = try ServerRepository(fileURL: stage.appendingPathComponent("servers.json")).load().map(relocated)
            let groups = try SessionGroupRepository(url: stage.appendingPathComponent("groups.json")).load()
            var sessions = try SessionRepository(url: stage.appendingPathComponent("sessions.json")).load()
            for index in sessions.indices {
                for tab in sessions[index].tabs.indices {
                    if let server = sessions[index].tabs[tab].server { sessions[index].tabs[tab].server = try relocated(server) }
                }
            }
            try ServerRepository(fileURL: stage.appendingPathComponent("servers.json")).save(servers)
            try SessionRepository(url: stage.appendingPathComponent("sessions.json")).save(sessions)
            try SessionArchive(servers: servers, groups: groups, sessions: sessions).validate()
            let credentials = SQLitePasswordStore(directory: stage.appendingPathComponent("Credentials"))
            for entry in try credentials.list() {
                let password = try credentials.read(entry.id)
                let parts = entry.id.split(separator: ":", maxSplits: 1)
                if parts.count == 2, let scope = scopes[String(parts[0])], scope != parts[0], let password {
                    try credentials.save(password, account: scope + ":" + parts[1], label: entry.label)
                    if let name = entry.name { try credentials.rename(scope + ":" + parts[1], name: name) }
                    try credentials.delete(entry.id)
                }
            }
            let props = try PropertyListSerialization.propertyList(from: backup.preferences, format: nil) as! [String: Any]
            let alert = NSAlert(); alert.messageText = L10n.text("恢复并替换当前偏好设置？")
            alert.informativeText = L10n.text("将替换会话、分组、密码、应用密钥和偏好设置，并关闭当前连接。历史文件保留；界面设置重启后生效。")
            alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("恢复"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            workspace.stopAll()
            try fm.createDirectory(at: previous, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let paths = ["servers.json", "groups.json", "sessions.json", "Credentials", "Keys"]
            var moved: [String] = [], installed: [String] = []
            do {
                for path in paths {
                    let target = root.appendingPathComponent(path)
                    if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: previous.appendingPathComponent(path)); moved.append(path) }
                    let replacement = stage.appendingPathComponent(path)
                    if fm.fileExists(atPath: replacement.path) { try fm.moveItem(at: replacement, to: target); installed.append(path) }
                }
            } catch {
                do {
                    for path in installed.reversed() { try fm.removeItem(at: root.appendingPathComponent(path)) }
                    for path in moved.reversed() { try fm.moveItem(at: previous.appendingPathComponent(path), to: root.appendingPathComponent(path)) }
                    try? fm.removeItem(at: previous)
                } catch { throw ConfigurationError.invalid("恢复失败，原文件备份保留在 \(previous.path)。请恢复后重启。") }
                throw error
            }
            try? fm.removeItem(at: previous)
            for key in PreferencesBackup.preferenceKeys {
                if let value = props[key] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            workspace.acceptRestoredConfiguration(servers: servers, groups: groups, saved: sessions)
            let done = NSAlert(); done.messageText = L10n.text("恢复完成，请重启应用以应用全部偏好设置。"); done.runModal()
        } catch { workspace.error = error.localizedDescription }
    }
}
