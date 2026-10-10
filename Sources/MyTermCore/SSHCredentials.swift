import Foundation
import CryptoKit

public protocol PasswordStore {
    func migrateScope(from: String, to: String) throws
    func migrateAccount(from: String, to: String) throws
    func read(_ account: String) throws -> String?
    func save(_ password: String, account: String) throws
    func save(_ password: String, account: String, label: String) throws
    func delete(_ account: String) throws
    func invalidateCachedPassword(_ account: String) throws
}
public extension PasswordStore {
    func migrateScope(from: String, to: String) throws {}
    func migrateAccount(from old: String, to new: String) throws {
        if let value = try read(old) {
            if try read(new) == nil { try save(value, account: new) }
            try delete(old)
        }
    }
    func save(_ password: String, account: String, label: String) throws { try save(password, account: account) }
    func invalidateCachedPassword(_ account: String) throws { try delete(account) }
}
/// Only OpenSSH's ordinary password prompt is reusable. OTPs, key passphrases,
/// host-key confirmations and password-change challenges remain interactive.
public final class SSHPasswordMemory {
    private let scope: String
    private let server: Server
    private let store: PasswordStore
    private let serverName: String
    private var labels: [String: String] = [:]
    private var attempted = Set<String>()
    private var pending: [String: String] = [:]
    /// Connection identity only: presentation, forwarding and authentication-method
    /// edits must not orphan a saved password. Keep endpoints/routes isolated.
    public static func scopeIdentifier(for server: Server) throws -> String {
        var identity = Server(id: server.id, host: server.host, user: server.user, port: server.port, jumpHost: server.jumpHost)
        identity.jumpServers = server.jumpServers?.map {
            SSHJumpServer(id: $0.id, host: $0.host, port: $0.port, user: $0.user)
        }
        return try legacyScopeIdentifier(for: identity)
    }
    public static func legacyScopeIdentifier(for server: Server) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(server)).map { String(format: "%02x", $0) }.joined()
    }
    public static func migrateLegacy(for server: Server, store: PasswordStore = SQLitePasswordStore()) throws {
        try store.migrateScope(from: legacyScopeIdentifier(for: server), to: scopeIdentifier(for: server))
    }
    public init(server: Server, store: PasswordStore = SQLitePasswordStore()) throws {
        try Self.migrateLegacy(for: server, store: store)
        scope = try Self.scopeIdentifier(for: server)
        self.store = store
        self.server = server
        serverName = server.displayName
        try migrateJumpPasswords()
    }
    private func migrateJumpPasswords() throws {
        for (index, hop) in (server.jumpServers ?? []).enumerated() {
            guard hop.authentication != .key, !hop.user.isEmpty else { continue }
            for host in [hop.host, "myterm-hop-\(server.id.uuidString.lowercased())-\(index + 1)"] {
                for prompt in ["\(hop.user)@\(host)'s password:", "(\(hop.user)@\(host)) Password:"] {
                    guard SSHJumpCredentials.matchingIndex(prompt: prompt, server: server) == index else { continue }
                    let old = scopedAccount(prompt), shared = try SSHJumpCredentials.account(server: server, index: index)
                    try store.migrateAccount(from: old, to: shared)
                }
            }
        }
    }
    public static func isPassword(_ prompt: String) -> Bool {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^[^\r\n]+@[^\r\n]+'s [Pp]assword:$"#, options: .regularExpression) != nil
            || value.range(of: #"^\([^\r\n]+@[^\r\n]+\) [Pp]assword:$"#, options: .regularExpression) != nil
    }
    private func account(_ prompt: String) -> String {
        if let index = SSHJumpCredentials.matchingIndex(prompt: prompt, server: server),
           let shared = try? SSHJumpCredentials.account(server: server, index: index) { return shared }
        return scopedAccount(prompt)
    }
    private func scopedAccount(_ prompt: String) -> String {
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
        if let index = SSHJumpCredentials.matchingIndex(prompt: prompt, server: server), let hop = server.jumpServers?[index] {
            labels[key] = SSHJumpCredentials.label(hop)
        } else {
            labels[key] = serverName + " · " + prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        pending[key] = remember ? password : nil
    }
    public func authenticated() throws {
        let values = pending; pending.removeAll()
        for (account, value) in values { try store.save(value, account: account, label: labels[account] ?? serverName) }
    }
    public func discard() { pending.removeAll() }
}
