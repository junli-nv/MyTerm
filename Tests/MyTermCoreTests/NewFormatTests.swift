import Foundation
import MyTermCore

func checkNewFormats() throws {
    let text = "你好世界\r\n\u{1b}[31mABC"
    for encoding in [TerminalEncoding.gb2312, .gbk, .gb18030, .big5] {
        let outgoing = try TerminalTranscoder(from: .utf8, to: encoding)
        let bytes = outgoing.convert(Array(text.utf8))
        let incoming = try TerminalTranscoder(from: encoding, to: .utf8)
        var output: [UInt8] = []
        for byte in bytes { output += incoming.convert([byte]) }
        checkEqual(String(decoding: output, as: UTF8.self), text)
    }
    let invalid = try TerminalTranscoder(from: .gbk, to: .utf8)
    checkEqual(String(decoding: invalid.convert([0xff, 65]), as: UTF8.self), "�A")
    let root = URL(fileURLWithPath: "/tmp/myterm-formats-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        if process.terminationStatus != 0 { throw ConfigurationError.invalid(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
        return String(decoding: data, as: UTF8.self)
    }
    let library = SSHKeyLibrary(directory: root.appendingPathComponent("keys"))
    for (name, args) in [("ed25519", ["-t", "ed25519", "-N", "test-passphrase"]), ("rsa", ["-t", "rsa", "-b", "2048", "-m", "PEM", "-N", ""])] {
        let original = root.appendingPathComponent(name)
        _ = try run("/usr/bin/ssh-keygen", args + ["-f", original.path, "-q"])
        try library.importKey(original)
        let key = try library.list().first { $0.name == name }!
        checkEqual(try Data(contentsOf: key.url), try Data(contentsOf: original))
        checkEqual((try FileManager.default.attributesOfItem(atPath: key.url.path)[.posixPermissions] as! NSNumber).intValue & 0o777, 0o600)
        checkThrows(try library.importKey(original))
        _ = try run("/usr/bin/ssh-keygen", ["-y", "-P", name == "ed25519" ? "test-passphrase" : "", "-f", key.url.path])
        try library.delete(key)
        checkEqual(FileManager.default.fileExists(atPath: original.path), true)
    }
    var server = Server(name: "Export", host: "example.com", user: "alice", port: "2222", identityFile: root.appendingPathComponent("rsa").path)
    server.forwards = [PortForward()]
    let config = root.appendingPathComponent("config")
    try Data(OpenSSHExport.render([server], userConfig: root.appendingPathComponent("optional-config").path).utf8).write(to: config)
    let rendered = try run("/usr/bin/ssh", ["-G", "-F", config.path, "example.com"])
    checkEqual(rendered.contains("user alice\n"), true)
    checkEqual(rendered.contains("port 2222\n"), true)
    checkEqual(rendered.contains("compression yes\n"), true)
    checkEqual(rendered.contains("localforward [127.0.0.1]:8080 [127.0.0.1]:80"), true)
    checkThrows(try OpenSSHExport.render([server, server]))
    checkFalse(rendered.contains("loglevel DEBUG3\n"))
    server.debugLogging = true
    let debugOptions = try run("/usr/bin/ssh", ["-G"] + server.sshArguments(configPath: "/dev/null"))
    checkEqual(debugOptions.contains("loglevel DEBUG3\n"), true)
    checkEqual(debugOptions.contains("escapechar none\n"), true)
    try Data(OpenSSHExport.render([server], userConfig: root.appendingPathComponent("optional-config").path).utf8).write(to: config)
    let debugExport = try run("/usr/bin/ssh", ["-G", "-F", config.path, server.host])
    checkEqual(debugExport.contains("loglevel DEBUG3\n"), true)
    server.jumpServers = [SSHJumpServer(host: "192.0.2.10", port: "2201", user: "first", authentication: .password),
                          SSHJumpServer(host: "192.0.2.20", port: "2202", user: "second", identityFile: root.appendingPathComponent("key with spaces").path, authentication: .key)]
    let restoredJumps = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(server))
    checkEqual(restoredJumps.jumpServers, server.jumpServers)
    let jumpConfig = root.appendingPathComponent("jumps-config")
    try Data(server.proxyJumpConfig(userConfig: root.appendingPathComponent("optional-config").path)!.utf8).write(to: jumpConfig)
    let aliases = server.effectiveJumpHost!.split(separator: ",").map(String.init)
    let firstHop = try run("/usr/bin/ssh", ["-G", "-F", jumpConfig.path, aliases[0]])
    let secondHop = try run("/usr/bin/ssh", ["-G", "-F", jumpConfig.path, aliases[1]])
    for expected in ["hostname 192.0.2.10\n", "port 2201\n", "user first\n", "pubkeyauthentication false\n", "passwordauthentication yes\n"] {
        checkEqual(firstHop.contains(expected), true)
    }
    for expected in ["hostname 192.0.2.20\n", "port 2202\n", "user second\n", "passwordauthentication no\n", "identitiesonly yes\n", "loglevel DEBUG3\n"] {
        checkEqual(secondHop.contains(expected), true)
    }
    checkEqual(secondHop.contains("identityfile " + server.jumpServers![1].identityFile + "\n"), true)
    try Data(OpenSSHExport.render([server], userConfig: root.appendingPathComponent("optional-config").path).utf8).write(to: config)
    let exportedJumps = try run("/usr/bin/ssh", ["-G", "-F", config.path, server.host])
    checkEqual(exportedJumps.contains("proxyjump " + server.effectiveJumpHost! + "\n"), true)
    checkEqual(try run("/usr/bin/ssh", ["-G", "-F", config.path, aliases[1]]).contains("user second\n"), true)
    var invalidJump = server
    invalidJump.jumpServers![0].port = "65536"; checkThrows(try invalidJump.validated())
    invalidJump = server; invalidJump.jumpHost = "legacy"; checkThrows(try invalidJump.validated())
    invalidJump = server; invalidJump.jumpServers = []; checkThrows(try invalidJump.validated())
    let store = SQLitePasswordStore(directory: root.appendingPathComponent("passwords"))
    try store.save("one", account: "test", label: "alice@example.com")
    checkEqual(try store.list().first?.label, "alice@example.com")
    try store.save("two", account: "test")
    checkEqual(try store.list().first?.label, "alice@example.com")
    checkEqual(try store.read("test"), "two")
    try store.delete("test"); checkEqual(try store.list().count, 0)
}
