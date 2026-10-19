import Foundation
import MyTermCore

func checkSharedJumpExport() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("shared-jump-export-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appendingPathComponent("config"), include = root.appendingPathComponent("optional").path
    var hop = SSHJumpServer(host: "192.0.2.68", port: "10022", user: "Administrator", authentication: .password, name: "WindowsVM")
    hop.profileID = hop.id
    var a = Server(name: "Region A", host: "target-a.test"), b = Server(name: "Region B", host: "target-b.test")
    a.jumpServers = [hop]; var copy = hop; copy.id = UUID(); b.jumpServers = [copy]
    func options(_ alias: String) throws -> [String: String] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-G", "-F", config.path, alias]; process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        checkEqual(process.terminationStatus, 0)
        return Dictionary(String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let pair = line.split(separator: " ", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { first, _ in first })
    }
    func write(_ servers: [Server]) throws -> String {
        let text = try OpenSSHExport.render(servers, userConfig: include)
        try Data(text.utf8).write(to: config); return text
    }
    func hosts(_ text: String) -> [String] { text.split(separator: "\n").filter { $0.hasPrefix("Host myterm-jump-") }.map { String($0.dropFirst(5)) } }
    let shared = try write([a, b])
    checkEqual(hosts(shared).count, 1)
    let alias = hosts(shared)[0]
    checkEqual(alias.hasPrefix("myterm-jump-windowsvm-"), true)
    checkEqual(try options(a.host)["proxyjump"], alias)
    checkEqual(try options(b.host)["proxyjump"], alias)
    let jump = try options(alias)
    checkEqual(jump["hostname"], hop.host); checkEqual(jump["user"], hop.user)
    checkEqual(jump["port"], "10022"); checkEqual(jump["pubkeyauthentication"], "false")
    checkEqual(hosts(try write([b, a])), [alias])
    checkEqual(shared, try write([a, b]))
    // Destination aliases and generated aliases must not shadow each other (case insensitive).
    let collision = Server(host: alias.uppercased())
    checkEqual(hosts(try write([a, b, collision])), [alias + "-2"])
    // Different effective settings must remain separate, even with the same profile ID.
    for variant in 0..<6 {
        var changed = b
        switch variant {
        case 0: changed.proxy = NetworkProxy(host: "127.0.0.1", port: "7890")
        case 1: changed.compression = false
        case 2: changed.debugLogging = true
        case 3: changed.jumpServers![0].authentication = .key
        case 4: changed.jumpServers![0].user = "other"
        default: changed.jumpServers![0].port = "2222"
        }
        checkEqual(hosts(try write([a, changed])).count, 2)
        checkFalse(try options(a.host)["proxyjump"] == options(changed.host)["proxyjump"])
    }
    // Multi-hop ordering stays at the destination; shared hops do not inherit another route.
    let second = SSHJumpServer(host: "192.0.2.69", user: "next", name: "第二跳")
    b.jumpServers = [copy, second]
    checkEqual(hosts(try write([a, b])).count, 2)
    let chain = try options(b.host)["proxyjump"]!.split(separator: ",").map(String.init)
    checkEqual(chain.count, 2); checkEqual(chain[0], alias)
    checkEqual(try options(chain[1])["hostname"], second.host)
    checkEqual(try options(chain[1])["proxyjump"], nil)
    // Name text never becomes wildcard/config directives; the original readable name stays in comments.
    b.jumpServers![1].editableName = "same * ? # 名称"
    let safe = try write([a, b])
    checkEqual(hosts(safe).allSatisfy { !$0.contains("*") && !$0.contains("?") && !$0.contains(" ") }, true)
    checkEqual(safe.contains("# Jump host: same * ? # 名称"), true)
}
