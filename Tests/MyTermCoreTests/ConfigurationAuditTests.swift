import Foundation
import MyTermCore

func checkConfigurationAudit() throws {
    var server = Server(name: "Destination", host: "destination.test", user: "alice", identityFile: "/valid/key")
    server.authentication = .key
    server.jumpServers = [SSHJumpServer(host: "removed-but-still-referenced.test", user: "jump", authentication: .password)]
    let account = try SSHJumpCredentials.account(server: server, index: 0)
    let references: [SSHConfigurationAudit.Reference] = [
        .init(server: server, source: "Current", exported: true),
        .init(server: server, source: "Snapshot", exported: false)]
    var checkedPaths: [String] = []
    let report = SSHConfigurationAudit.inspect(references, passwordAccounts: [account, "unrelated:password"], keyAvailable: { checkedPaths.append($0); return $0 == "/valid/key" })
    checkEqual(report.rows.count, 4)
    checkEqual(report.rows.filter(\.exported).count, 2)
    checkEqual(report.rows[1].host, "removed-but-still-referenced.test")
    checkEqual(report.rows[1].password, .saved)
    checkEqual(report.rows[0].password, .notUsed)
    checkEqual(report.rows[0].keyAvailable, true)
    checkEqual(report.unusedPasswordAccounts, ["unrelated:password"])
    checkEqual(checkedPaths, ["/valid/key", "/valid/key"])
    server.authentication = .password
    server.jumpServers = nil
    let noPassword = SSHConfigurationAudit.inspect([.init(server: server, source: "A", exported: true)], passwordAccounts: [])
    checkEqual(noPassword.rows[0].password, .absent)
    checkEqual(noPassword.rows[0].keyAvailable, nil) // Disabled key settings are not active dependencies.
    server.authentication = .key
    let missing = SSHConfigurationAudit.inspect([.init(server: server, source: "A", exported: true)], passwordAccounts: [], keyAvailable: { _ in false })
    checkEqual(missing.rows[0].keyAvailable, false)
    server.authentication = .automatic; server.user = ""; server.jumpHost = "external-hop"
    let unknown = SSHConfigurationAudit.inspect([.init(server: server, source: "A", exported: true)], passwordAccounts: nil)
    checkEqual(unknown.rows[0].password, .unavailable)
    checkEqual(unknown.rows[0].externalJump, "external-hop")
    let unspecified = SSHConfigurationAudit.inspect([.init(server: server, source: "A", exported: true)], passwordAccounts: [])
    checkEqual(unspecified.rows[0].password, .unspecifiedUser)
}
