import Foundation

/// A metadata-only inventory. No password decryption, SSH execution or network probing.
public enum SSHConfigurationAudit {
    public struct Reference {
        public let server: Server
        public let source: String
        public let exported: Bool
        public init(server: Server, source: String, exported: Bool) {
            self.server = server; self.source = source; self.exported = exported
        }
    }
    public enum PasswordStatus { case saved, absent, unspecifiedUser, notUsed, unavailable }
    public struct Row: Identifiable {
        public let id: Int
        public let source: String
        public let host: String
        public let user: String
        public let port: String
        public let hop: Int?
        public let profileID: UUID?
        public let exported: Bool
        public let password: PasswordStatus
        public let keyPath: String
        public let keyAvailable: Bool?
        public let externalJump: String?
    }
    public struct Result {
        public let rows: [Row]
        public let unusedPasswordAccounts: Set<String>
    }
    public static func inspect(_ references: [Reference], passwordAccounts: Set<String>?,
                               keyAvailable: (String) -> Bool = { path in
                                   var directory: ObjCBool = false
                                   return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue && FileManager.default.isReadableFile(atPath: path)
                               }) -> Result {
        var rows: [Row] = [], matched = Set<String>()
        for ref in references {
            let server = ref.server
            let scopes = [try? SSHPasswordMemory.scopeIdentifier(for: server), try? SSHPasswordMemory.legacyScopeIdentifier(for: server)].compactMap { $0 }
            let destinationAccounts = Set((passwordAccounts ?? []).filter { account in scopes.contains { account.hasPrefix($0 + ":") } })
            matched.formUnion(destinationAccounts)
            func append(host: String, user: String, port: String, mode: AuthenticationMode, identity: String,
                        hop: Int?, profile: UUID?, accounts: Set<String>) {
                matched.formUnion(accounts)
                let status: PasswordStatus
                if mode == .key { status = .notUsed }
                else if passwordAccounts == nil { status = .unavailable }
                else if user.isEmpty { status = .unspecifiedUser }
                else { status = accounts.isEmpty ? .absent : .saved }
                let path = mode == .password ? "" : (identity as NSString).expandingTildeInPath
                rows.append(Row(id: rows.count, source: ref.source, host: host, user: user, port: port,
                                hop: hop, profileID: profile, exported: ref.exported, password: status,
                                keyPath: path, keyAvailable: path.isEmpty ? nil : keyAvailable(path),
                                externalJump: hop == nil ? server.jumpHost : nil))
            }
            append(host: server.host, user: server.user, port: server.port, mode: server.authentication ?? .automatic,
                   identity: server.identityFile, hop: nil, profile: nil, accounts: destinationAccounts)
            for (index, hop) in (server.jumpServers ?? []).enumerated() {
                let account = try? SSHJumpCredentials.account(server: server, index: index)
                let accounts = Set((passwordAccounts ?? []).filter { $0 == account })
                append(host: hop.host, user: hop.user, port: hop.port, mode: hop.authentication, identity: hop.identityFile,
                       hop: index + 1, profile: hop.profileID, accounts: accounts)
            }
        }
        return Result(rows: rows, unusedPasswordAccounts: (passwordAccounts ?? []).subtracting(matched))
    }
}
