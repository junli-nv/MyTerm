import Foundation
import CryptoKit
import CCommonCrypto

public struct PreferencesBackup: Codable {
    public var version = 1
    public var files: [String: Data]
    public var preferences: Data
    public init(files: [String: Data], preferences: Data) { self.files = files; self.preferences = preferences }
    public static let preferenceKeys = ["terminal.theme", "terminal.outputHighlight", "mouse.rightClickPastes", "mouse.copyOnSelection", "terminal.disableBell", "layout.sidebarHidden", "interface.language", "AppleLanguages"]
    private struct Envelope: Codable { var version: Int; var salt: Data; var sealed: Data }
    private static func key(_ passphrase: String, salt: Data) throws -> SymmetricKey {
        guard !passphrase.isEmpty, passphrase.utf8.count <= 4096, salt.count == 16 else { throw ConfigurationError.invalid("备份口令或盐值无效。") }
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let result = password.withUnsafeBytes { pass in salt.withUnsafeBytes { salt in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                salt.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 310_000, &derived, derived.count)
        } }
        guard result == kCCSuccess else { throw ConfigurationError.invalid("无法生成备份加密密钥。") }
        return SymmetricKey(data: derived)
    }
    public func validate() throws {
        guard version == 1, files.count <= 10000 else { throw ConfigurationError.invalid("不支持的备份格式。") }
        for (path, data) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let config = ["servers.json", "groups.json", "sessions.json"].contains(path)
            let credential = ["Credentials/passwords.sqlite", "Credentials/encryption.key"].contains(path)
            let key = parts.count == 2 && parts[0] == "Keys" && !parts[1].hasPrefix(".") && !parts[1].contains("\\")
            guard (config || credential || key), !path.contains("\0"), data.count <= 64 * 1024 * 1024 else { throw ConfigurationError.invalid("备份包含不允许的文件路径或超大文件。") }
        }
        guard (files["Credentials/passwords.sqlite"] == nil) == (files["Credentials/encryption.key"] == nil) else { throw ConfigurationError.invalid("备份密码库与密钥不完整。") }
        let props = try PropertyListSerialization.propertyList(from: preferences, format: nil)
        guard let dictionary = props as? [String: Any], Set(dictionary.keys).isSubset(of: Set(Self.preferenceKeys)) else { throw ConfigurationError.invalid("备份偏好设置无效。") }
        if let saved = dictionary["terminal.outputHighlight"] {
            guard let data = saved as? Data else { throw ConfigurationError.invalid("备份偏好设置无效。") }
            try JSONDecoder().decode(OutputHighlightConfiguration.self, from: data).validate()
        }
    }
    public func encrypted(passphrase: String) throws -> Data {
        try validate()
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let key = try Self.key(passphrase, salt: salt)
        let clear = try JSONEncoder().encode(self)
        guard clear.count <= 64 * 1024 * 1024 else { throw ConfigurationError.invalid("备份不能超过 64 MB。") }
        let sealed = try AES.GCM.seal(clear, using: key, authenticating: Data("MyTerm Preferences Backup v1".utf8))
        return try JSONEncoder().encode(Envelope(version: 1, salt: salt, sealed: sealed.combined!))
    }
    public static func decrypt(_ data: Data, passphrase: String) throws -> PreferencesBackup {
        guard data.count <= 90 * 1024 * 1024 else { throw ConfigurationError.invalid("备份文件过大。") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw ConfigurationError.invalid("不支持的备份版本。") }
        let clear: Data
        do { clear = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key(passphrase, salt: envelope.salt), authenticating: Data("MyTerm Preferences Backup v1".utf8)) }
        catch { throw ConfigurationError.invalid("备份口令不正确，或文件已损坏。") }
        let value = try JSONDecoder().decode(Self.self, from: clear); try value.validate(); return value
    }
}
