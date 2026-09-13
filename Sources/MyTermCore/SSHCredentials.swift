import Foundation
import CryptoKit

public protocol PasswordStore {
    func read(_ account: String) throws -> String?
    func save(_ password: String, account: String) throws
    func save(_ password: String, account: String, label: String) throws
    func delete(_ account: String) throws
    func invalidateCachedPassword(_ account: String) throws
}
public extension PasswordStore {
    func save(_ password: String, account: String, label: String) throws { try save(password, account: account) }
    func invalidateCachedPassword(_ account: String) throws { try delete(account) }
}
/// Only OpenSSH's ordinary password prompt is reusable. OTPs, key passphrases,
/// host-key confirmations and password-change challenges remain interactive.
public final class SSHPasswordMemory {
    private let scope: String
    private let store: PasswordStore
    private let serverName: String
    private var labels: [String: String] = [:]
    private var attempted = Set<String>()
    private var pending: [String: String] = [:]
    public static func scopeIdentifier(for server: Server) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(server)).map { String(format: "%02x", $0) }.joined()
    }
    public init(server: Server, store: PasswordStore = SQLitePasswordStore()) throws {
        scope = try Self.scopeIdentifier(for: server)
        self.store = store
        serverName = server.displayName
    }
    public static func isPassword(_ prompt: String) -> Bool {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^[^\r\n]+@[^\r\n]+'s [Pp]assword:$"#, options: .regularExpression) != nil
            || value.range(of: #"^\([^\r\n]+@[^\r\n]+\) [Pp]assword:$"#, options: .regularExpression) != nil
    }
    private func account(_ prompt: String) -> String {
        scope + ":" + SHA256.hash(data: Data(prompt.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func wasAttempted(_ prompt: String) -> Bool { attempted.contains(account(prompt)) }
    public func cached(_ prompt: String) throws -> String? {
        guard Self.isPassword(prompt) else { return nil }
        let key = account(prompt)
        pending[key] = nil // A repeated challenge rejects the last candidate.
        guard !attempted.contains(key) else { try store.invalidateCachedPassword(key); return nil }
        attempted.insert(key)
        return try store.read(key)
    }
    public func submitted(_ password: String, prompt: String, remember: Bool) {
        guard Self.isPassword(prompt) else { return }
        let key = account(prompt); attempted.insert(key)
        labels[key] = serverName + " · " + prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        pending[key] = remember ? password : nil
    }
    public func authenticated() throws {
        let values = pending; pending.removeAll()
        for (account, value) in values { try store.save(value, account: account, label: labels[account] ?? serverName) }
    }
    public func discard() { pending.removeAll() }
}
