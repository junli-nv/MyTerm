import Foundation
import MyTermCore

func checkBackupAndRates() throws {
    var rate = FileTransferRate()
    checkEqual(rate.sample(now: 0), 0)
    rate.update(completed: 900000, now: 0)
    rate.update(completed: 901000, now: 1)
    checkEqual(rate.sample(now: 1), 1000)
    rate.update(completed: 902000, now: 2)
    checkEqual(rate.sample(now: 2), 1000)
    checkEqual(rate.sample(now: 3), 500)
    checkEqual(rate.sample(now: 4), 0)
    checkEqual(rate.average(now: 4), 500)
    checkEqual(rate.transferred, 2000)
    let root = URL(fileURLWithPath: "/tmp/myterm-backup-check-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SQLitePasswordStore(directory: root.appendingPathComponent("source"))
    try store.save("synthetic-backup-password", account: "test", label: "test@example.com")
    let props = try PropertyListSerialization.data(fromPropertyList: ["mouse.copyOnSelection": true, "interface.language": "english"], format: .binary, options: 0)
    let backup = PreferencesBackup(files: try store.backupFiles(), preferences: props)
    let encrypted = try backup.encrypted(passphrase: "synthetic backup passphrase")
    checkFalse(encrypted.range(of: Data("synthetic-backup-password".utf8)) != nil)
    checkThrows(try PreferencesBackup.decrypt(encrypted, passphrase: "wrong"))
    var envelope = try JSONSerialization.jsonObject(with: encrypted) as! [String: Any]
    var sealed = Data(base64Encoded: envelope["sealed"] as! String)!
    sealed[sealed.count / 2] ^= 1; envelope["sealed"] = sealed.base64EncodedString()
    checkThrows(try PreferencesBackup.decrypt(JSONSerialization.data(withJSONObject: envelope), passphrase: "synthetic backup passphrase"))
    let restored = try PreferencesBackup.decrypt(encrypted, passphrase: "synthetic backup passphrase")
    checkEqual(restored.preferences, props); checkEqual(restored.files, backup.files)
    let target = root.appendingPathComponent("restored")
    for (name, bytes) in restored.files {
        let file = target.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
    }
    checkEqual(try SQLitePasswordStore(directory: target.appendingPathComponent("Credentials")).read("test"), "synthetic-backup-password")
    var invalid = backup; invalid.files["Keys/../../outside"] = Data()
    checkThrows(try invalid.validate())
    invalid = backup; invalid.files["Credentials/encryption.key"] = nil
    checkThrows(try invalid.validate())
    var server = Server(host: "example.com")
    checkEqual(try server.connectionArguments().contains("ForwardX11=no"), true)
    server.x11Forwarding = .untrusted
    checkEqual(try server.connectionArguments().contains("ForwardX11=yes"), true)
    checkEqual(try server.connectionArguments().contains("ForwardX11Trusted=no"), true)
    server.x11Forwarding = .trusted
    checkEqual(try server.connectionArguments().contains("ForwardX11Trusted=yes"), true)
    let exported = try OpenSSHExport.render([server])
    checkEqual(exported.contains("ForwardX11Trusted \"yes\""), true)
}
