import Foundation

public struct ManagedSSHKey: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public var name: String { url.lastPathComponent }
}
public struct SSHKeyLibrary {
    public let directory: URL
    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyTerm/Keys")) { self.directory = directory }
    public func list() throws -> [ManagedSSHKey] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { !$0.lastPathComponent.hasSuffix(".pub") && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { ManagedSSHKey(url: $0) }
    }
    public func importKey(_ source: URL) throws {
        let fm = FileManager.default
        guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1024 * 1024 else { throw ConfigurationError.invalid("密钥文件过大。") }
        let data = try Data(contentsOf: source)
        let header = String(decoding: data.prefix(100), as: UTF8.self)
        guard ["OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "DSA PRIVATE KEY", "PRIVATE KEY", "ENCRYPTED PRIVATE KEY"].contains(where: { header.hasPrefix("-----BEGIN \($0)-----") }) else {
            throw ConfigurationError.invalid("请选择 ssh-keygen / OpenSSH 或 PEM 格式的私钥；公钥和 PuTTY PPK 不能作为私钥导入。")
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw ConfigurationError.invalid("密钥库目录不能是符号链接。") }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let target = directory.appendingPathComponent(source.lastPathComponent)
        guard !source.lastPathComponent.hasSuffix(".pub"), !source.lastPathComponent.hasPrefix("."), !fm.fileExists(atPath: target.path) else { throw ConfigurationError.invalid("密钥名称无效或已有同名密钥，请更名后导入。") }
        try data.write(to: target, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let publicSource = URL(fileURLWithPath: source.path + ".pub")
        if fm.fileExists(atPath: publicSource.path) {
            do {
                guard (try publicSource.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1024 * 1024 else { throw ConfigurationError.invalid("公钥文件过大。") }
                let publicData = try Data(contentsOf: publicSource)
                let publicText = String(decoding: publicData, as: UTF8.self)
                guard !publicText.contains("PRIVATE KEY"), publicText.hasPrefix("ssh-") || publicText.hasPrefix("ecdsa-") || publicText.hasPrefix("sk-") else { throw ConfigurationError.invalid("附带的 .pub 文件不是 OpenSSH 公钥。") }
                try publicData.write(to: URL(fileURLWithPath: target.path + ".pub"), options: .withoutOverwriting)
            } catch { try? fm.removeItem(at: target); throw error }
        }
    }
    public func delete(_ key: ManagedSSHKey) throws {
        guard key.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else { throw ConfigurationError.invalid("只能删除应用密钥库内的密钥。") }
        try FileManager.default.removeItem(at: key.url)
        let pub = URL(fileURLWithPath: key.url.path + ".pub")
        if FileManager.default.fileExists(atPath: pub.path) { try FileManager.default.removeItem(at: pub) }
    }
}
