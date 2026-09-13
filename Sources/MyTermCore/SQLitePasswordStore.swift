import Foundation
import CryptoKit
import CSQLite
import Darwin

public struct StoredPasswordInfo: Identifiable {
    public let id: String
    public let label: String
    public let name: String?
    public var displayName: String { name ?? label }
}

/// App-owned encrypted credential database. The local key is deliberately independent
/// of Keychain. Possession of BOTH database and key permits decryption.
public struct SQLitePasswordStore: PasswordStore {
    public let directory: URL
    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyTerm/Credentials")) {
        self.directory = directory
    }
    private var databaseURL: URL { directory.appendingPathComponent("passwords.sqlite") }
    private var keyURL: URL { directory.appendingPathComponent("encryption.key") }
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func access<T>(_ action: (OpaquePointer, SymmetricKey) throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw failure("密码目录不能是符号链接。") }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lock = Darwin.open(directory.appendingPathComponent("store.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw failure("无法锁定本地密码存储。") }
        defer { flock(lock, LOCK_UN); Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw failure("无法锁定本地密码存储。") }
        for url in [keyURL, databaseURL] where fm.fileExists(atPath: url.path) {
            guard (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw failure("密码存储文件不能是符号链接。") }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let key: SymmetricKey
        if fm.fileExists(atPath: keyURL.path) {
            let bytes = try Data(contentsOf: keyURL)
            guard bytes.count == 32 else { throw failure("本地密码密钥损坏，请恢复原密钥文件。") }
            key = SymmetricKey(data: bytes)
        } else {
            guard !fm.fileExists(atPath: databaseURL.path) else { throw failure("本地密码密钥缺失，请恢复 encryption.key；原数据库已保留。") }
            key = SymmetricKey(size: .bits256)
            try key.withUnsafeBytes { try Data($0).write(to: keyURL, options: .atomic) }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        let file = Darwin.open(databaseURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw failure("无法打开本地密码数据库。") }
        Darwin.close(file)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard let db = handle else { throw failure("无法打开本地密码数据库。") }
        defer { sqlite3_close(db) }
        try check(result)
        sqlite3_busy_timeout(db, 5000)
        try check(sqlite3_exec(db, "PRAGMA secure_delete=ON", nil, nil, nil))
        try check(sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS credentials (account TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)", nil, nil, nil))
        try check(sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS credential_labels (account TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL)", nil, nil, nil))
        try check(sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS credential_names (account TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL)", nil, nil, nil))
        return try action(db, key)
    }
    private func statement(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        if code != SQLITE_OK { if let statement { sqlite3_finalize(statement) }; try check(code) }
        guard let statement else { throw failure("无法准备密码数据库操作。") }; return statement
    }
    public func read(_ account: String) throws -> String? {
        try access { db, key in
            let query = try statement(db, "SELECT sealed FROM credentials WHERE account = ?")
            defer { sqlite3_finalize(query) }
            try check(sqlite3_bind_text(query, 1, account, -1, transient))
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { try check(result); return nil }
            let count = Int(sqlite3_column_bytes(query, 0))
            guard count >= 28, count <= 65536, let bytes = sqlite3_column_blob(query, 0) else { throw failure("已保存的密码数据损坏。") }
            do {
                let box = try AES.GCM.SealedBox(combined: Data(bytes: bytes, count: count))
                let clear = try AES.GCM.open(box, using: key, authenticating: Data(account.utf8))
                guard let password = String(data: clear, encoding: .utf8) else { throw failure("密码编码无效。") }
                return password
            } catch { throw failure("无法解密已保存的密码，请检查数据库和密钥是否匹配。") }
        }
    }
    public func save(_ password: String, account: String) throws {
        try saveEntry(password, account: account, label: nil)
    }
    public func save(_ password: String, account: String, label: String) throws {
        try saveEntry(password, account: account, label: label)
    }
    private func saveEntry(_ password: String, account: String, label: String?) throws {
        guard password.utf8.count <= 60000 else { throw failure("密码长度超出限制。") }
        try access { db, key in
            try check(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil))
            defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
            guard let sealed = try AES.GCM.seal(Data(password.utf8), using: key, authenticating: Data(account.utf8)).combined else { throw failure("无法加密密码。") }
            let query = try statement(db, "INSERT INTO credentials(account, sealed) VALUES(?, ?) ON CONFLICT(account) DO UPDATE SET sealed = excluded.sealed")
            defer { sqlite3_finalize(query) }
            try check(sqlite3_bind_text(query, 1, account, -1, transient))
            try sealed.withUnsafeBytes { try check(sqlite3_bind_blob(query, 2, $0.baseAddress, Int32($0.count), transient)) }
            try check(sqlite3_step(query))
            if let label {
                let metadata = try statement(db, "INSERT INTO credential_labels(account, label) VALUES(?, ?) ON CONFLICT(account) DO UPDATE SET label = excluded.label")
                defer { sqlite3_finalize(metadata) }
                try check(sqlite3_bind_text(metadata, 1, account, -1, transient))
                try check(sqlite3_bind_text(metadata, 2, label, -1, transient))
                try check(sqlite3_step(metadata))
            }
            try check(sqlite3_exec(db, "COMMIT", nil, nil, nil))
        }
    }
    public func delete(_ account: String) throws {
        try access { db, _ in
            let query = try statement(db, "DELETE FROM credentials WHERE account = ?")
            defer { sqlite3_finalize(query) }
            try check(sqlite3_bind_text(query, 1, account, -1, transient)); try check(sqlite3_step(query))
            let metadata = try statement(db, "DELETE FROM credential_labels WHERE account = ?")
            defer { sqlite3_finalize(metadata) }
            try check(sqlite3_bind_text(metadata, 1, account, -1, transient)); try check(sqlite3_step(metadata))
            let name = try statement(db, "DELETE FROM credential_names WHERE account = ?")
            defer { sqlite3_finalize(name) }
            try check(sqlite3_bind_text(name, 1, account, -1, transient)); try check(sqlite3_step(name))
        }
    }
    public func deleteAll() throws {
        try access { db, _ in try check(sqlite3_exec(db, "DELETE FROM credentials; DELETE FROM credential_labels; DELETE FROM credential_names", nil, nil, nil)) }
    }
    public func rename(_ account: String, name: String) throws {
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure("密码名称不能包含控制字符。") }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 120 else { throw failure("密码名称最多 120 个字符。") }
        try access { db, _ in
            let query = try statement(db, "INSERT INTO credential_names(account, name) SELECT account, ? FROM credentials WHERE account = ? ON CONFLICT(account) DO UPDATE SET name = excluded.name")
            defer { sqlite3_finalize(query) }
            try check(sqlite3_bind_text(query, 1, value, -1, transient))
            try check(sqlite3_bind_text(query, 2, account, -1, transient))
            try check(sqlite3_step(query))
            guard sqlite3_changes(db) > 0 else { throw failure("密码记录已不存在，请刷新。") }
        }
    }
    public func invalidateCachedPassword(_ account: String) throws {
        // A rejected password must not be reused, but its user-assigned name
        // should survive when successful authentication replaces the secret.
        try access { db, _ in
            let query = try statement(db, "DELETE FROM credentials WHERE account = ?")
            defer { sqlite3_finalize(query) }
            try check(sqlite3_bind_text(query, 1, account, -1, transient)); try check(sqlite3_step(query))
        }
    }
    public func list() throws -> [StoredPasswordInfo] {
        try access { db, _ in
            let query = try statement(db, "SELECT c.account, l.label, n.name FROM credentials c LEFT JOIN credential_labels l ON c.account = l.account LEFT JOIN credential_names n ON c.account = n.account ORDER BY COALESCE(NULLIF(n.name, ''), l.label), c.account")
            defer { sqlite3_finalize(query) }
            var result: [StoredPasswordInfo] = []
            while true {
                let code = sqlite3_step(query)
                if code == SQLITE_DONE { return result }
                guard code == SQLITE_ROW else { try check(code); return result }
                let account = String(cString: sqlite3_column_text(query, 0))
                let label = sqlite3_column_text(query, 1).map { String(cString: $0) } ?? "旧版密码 · \(account.prefix(12))…"
                let name = sqlite3_column_text(query, 2).map { String(cString: $0) }
                result.append(StoredPasswordInfo(id: account, label: label, name: name?.isEmpty == false ? name : nil))
            }
        }
    }
    public func backupFiles() throws -> [String: Data] {
        try access { _, _ in
            ["Credentials/passwords.sqlite": try Data(contentsOf: databaseURL), "Credentials/encryption.key": try Data(contentsOf: keyURL)]
        }
    }
    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK || code == SQLITE_DONE else { throw failure("本地密码数据库操作失败（\(code)）。") }
    }
    private func failure(_ message: String) -> ConfigurationError { .invalid(message) }
}
