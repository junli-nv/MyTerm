import Foundation
import MyTermCore

final class ServerTests {
    func testAliasKeepsSSHConfigDefaults() throws {
        let args = try Server(host: "dev-alias").sshArguments()
        checkEqual(Array(args.suffix(2)), ["--", "dev-alias"])
        checkFalse(args.contains("-p"))
        checkFalse(args.contains("-l"))
        checkEqual(args.contains("ServerAliveInterval=30"), true)
        checkEqual(args.contains("ServerAliveCountMax=6"), true)
        checkEqual(args.contains("TCPKeepAlive=yes"), true)
        checkEqual(args.contains("StrictHostKeyChecking=no"), true)
        checkEqual(try Server(host: "dev-alias").sftpArguments(controlPath: "/tmp/control").contains("StrictHostKeyChecking=no"), true)
    }

    func testArgumentsPreserveKeyPathAsSingleArgument() throws {
        let args = try Server(host: "2001:db8::1", user: "dev", port: "2222", identityFile: "/tmp/my key;literal").sshArguments()
        checkEqual(Array(args.suffix(8)), ["-p", "2222", "-l", "dev", "-i", "/tmp/my key;literal", "--", "2001:db8::1"])
    }

    func testRejectsHostOptionAndCommandInjection() {
        for host in ["-oProxyCommand=touch", "server;touch /tmp/x", "server\ncommand", "user@host", "$(whoami)", ""] {
            checkThrows(try Server(host: host).sshArguments(), host)
        }
    }

    func testRejectsInvalidPort() {
        for port in ["0", "65536", "abc", "22 -o test"] {
            checkThrows(try Server(host: "localhost", port: port).validated())
        }
    }

    func testRepositoryRoundTripAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ServerRepository(fileURL: directory.appendingPathComponent("servers.json"))
        checkEqual(try repository.load(), [])
        let server = Server(name: "开发", host: "example.com", user: "dev")
        try repository.save([server])
        checkEqual(try repository.load(), [server])
        try Data("broken".utf8).write(to: repository.fileURL)
        checkThrows(try repository.load())
        checkEqual(try String(contentsOf: repository.fileURL, encoding: .utf8), "broken")
    }
}
