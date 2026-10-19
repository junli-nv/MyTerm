import MyTermCore

/// A test may read existing route credentials, but draft passwords and all mutations
/// remain in memory until the user explicitly saves the jump profile.
final class JumpTestPasswordStore: PasswordStore {
    private let base: PasswordStore
    private var values: [String: String]
    private var removed = Set<String>()
    init(base: PasswordStore, account: String, password: String) {
        self.base = base; values = [account: password]
    }
    func read(_ account: String) throws -> String? {
        if removed.contains(account) { return nil }
        return try values[account] ?? base.read(account)
    }
    func save(_ password: String, account: String) throws { values[account] = password; removed.remove(account) }
    func delete(_ account: String) throws { values.removeValue(forKey: account); removed.insert(account) }
}
