import Foundation
import MyTermCore

final class FeatureTests {
    func connectionOptions() throws {
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"old","host":"target","user":"","port":"","identityFile":""}"#.utf8)
        var server = try JSONDecoder().decode(Server.self, from: legacy)
        checkEqual(server.compression ?? true, true)
        checkEqual(try server.sshArguments().contains("Compression=yes"), true)
        checkEqual(server.debugLogging ?? false, false)
        checkFalse(try server.sshArguments().contains("-vvv"))
        server.debugLogging = true
        checkEqual(try server.sshArguments().contains("-vvv"), true)
        checkFalse(try server.sftpArguments(controlPath: "/tmp/check").contains("-vvv"))
        let restoredDebug = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(server))
        checkEqual(restoredDebug.debugLogging, true)
        checkEqual(try restoredDebug.sshArguments().contains("-vvv"), true)
        server.debugLogging = false
        checkFalse(try server.sshArguments().contains("-vvv"))
        server.jumpHost = "dev@bastion:2222,second"
        server.proxy = NetworkProxy(kind: .http, host: "127.0.0.1", port: "7890")
        server.authentication = .password
        server.forwards = [PortForward(), PortForward(kind: .remote, listenPort: "9000"), PortForward(kind: .dynamic, listenPort: "1080")]
        let args = try server.sshArguments(controlPath: "/tmp/example", configPath: "/tmp/config")
        checkEqual(args.contains("-J"), true); checkEqual(args.contains("PubkeyAuthentication=no"), true)
        checkEqual(args.contains("PasswordAuthentication=yes"), true)
        checkEqual(args.contains("KbdInteractiveAuthentication=yes"), true)
        checkEqual(args.contains("-L"), true); checkEqual(args.contains("-R"), true); checkEqual(args.contains("-D"), true)
        checkEqual(args.contains("ExitOnForwardFailure=yes"), true)
        let config = try server.proxyJumpConfig(userConfig: "/tmp/config original")!
        checkEqual(config.contains("Host bastion\n"), true)
        checkEqual(config.contains(" http "), true)
        checkFalse(args.contains(where: { $0.hasPrefix("ProxyCommand=") }))
        let sftp = try server.sftpArguments(controlPath: "/tmp/example", configPath: "/tmp/config")
        checkFalse(sftp.contains("-L")); checkEqual(sftp.contains("ClearAllForwardings=yes"), true)
        server.jumpHost = nil; server.proxy?.kind = .socks5; server.authentication = .key; server.compression = false
        let direct = try server.sshArguments()
        checkEqual(direct.contains("PreferredAuthentications=publickey"), true)
        checkEqual(direct.contains("PasswordAuthentication=no"), true)
        checkEqual(direct.contains("KbdInteractiveAuthentication=no"), true)
        checkEqual(direct.contains("Compression=no"), true)
        checkEqual(direct.contains(where: { $0.contains("MyTermProxy' socks5") }), true)
        for jump in ["-oProxyCommand=x", "host:0", "host:65536", "one,,two", "host;touch /tmp/no"] {
            server.jumpHost = jump; checkThrows(try server.validated())
        }
        server.jumpHost = nil; server.proxy?.host = "localhost' command"
        checkThrows(try server.validated())
    }

    func importAndSessions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("hosts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("Host * !excluded\n User ignored\nHost alpha beta # comment\nInclude hosts/*.conf\nMatch exec \"touch NEVER\"\n".utf8).write(to: directory.appendingPathComponent("config"))
        try Data("Host=\"gamma\"\nHost alpha wildcard*\nInclude config\n".utf8).write(to: directory.appendingPathComponent("hosts/one.conf"))
        let imported = try SSHConfigImporter(root: directory.appendingPathComponent("config")).discover()
        checkEqual(imported.map(\.alias), ["alpha", "beta", "gamma"])
        checkEqual(imported[0].server.user, "")
        let repo = SessionRepository(url: directory.appendingPathComponent("sessions.json"))
        let saved = SavedSession(name: "工作区", tabs: [SessionTab(), SessionTab(server: Server(host: "alpha", jumpHost: "beta"))], selectedIndex: 1)
        try repo.save([saved]); checkEqual(try repo.load(), [saved])
        try Data("bad".utf8).write(to: repo.url); checkThrows(try repo.load())
    }

    func zmodemDetection() {
        let header = Data([42, 42, 24, 66]) + Data("00000000000000\r\n".utf8)
        for split in 0...header.count {
            var detector = ZmodemDetector()
            let first = detector.feed(Data("hello".utf8) + header.prefix(split))
            if first.handshake != nil {
                checkEqual(first.visible, Data("hello".utf8)); checkEqual(first.receiving, true)
                continue // Remaining bytes now belong to the active protocol, not the detector.
            }
            let second = detector.feed(Data(header.dropFirst(split)))
            let rendered = String(decoding: first.visible + second.visible, as: UTF8.self)
            checkEqual(["hello", "hello*", "hello**"].contains(rendered), true)
            checkEqual(second.handshake.map { $0.starts(with: header.prefix(18)) }, true)
            checkEqual(first.handshake != nil || second.handshake != nil, true)
            checkEqual(first.receiving || second.receiving, true)
        }
        var detector = ZmodemDetector()
        checkEqual(detector.feed(Data("normal output".utf8)).visible, Data("normal output".utf8))
        // Each keystroke must be visible in the same read, without another key
        // or a timer; subsequent output must never duplicate the prefix.
        for text in ["*", "*", "*", "x", "\\", "*", " ", "**", "ok"] {
            checkEqual(detector.feed(Data(text.utf8)).visible, Data(text.utf8))
        }
        let malformed = Data([42, 42, 24, 66]) + Data("not-a-header!!\r\nX".utf8)
        for split in 0...malformed.count {
            var parser = ZmodemDetector()
            let a = parser.feed(Data(malformed.prefix(split)))
            let b = parser.feed(Data(malformed.dropFirst(split)))
            checkEqual(a.visible + b.visible, malformed)
            checkEqual(a.handshake == nil && b.handshake == nil, true)
        }
        for type in ["00", "01"] {
            let frame = Data([42, 42, 24, 66]) + Data((type + "000000000000").utf8)
            var parser = ZmodemDetector()
            var protocolBytes: Data?
            for byte in frame {
                let result = parser.feed(Data([byte]))
                if let handshake = result.handshake { protocolBytes = handshake; checkEqual(result.receiving, type == "00") }
            }
            checkEqual(protocolBytes, frame)
            checkEqual(parser.feed(Data("*".utf8)).visible, Data("*".utf8))
        }
    }

    func sftpResume() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("myterm-sftp-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote"), local = root.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func client() throws -> SFTPClient {
            let value = SFTPClient(executable: "/usr/libexec/sftp-server", arguments: ["-d", remote.path])
            try value.connect(); return value
        }
        let original = Data((0..<250000).map { UInt8(truncatingIfNeeded: $0 * 31) })
        let source = local.appendingPathComponent("中文 file ' ; $.bin")
        try original.write(to: source)
        let target = remote.appendingPathComponent(source.lastPathComponent).path
        let first = try client()
        checkEqual(try first.realpath(".").hasSuffix("/\(root.lastPathComponent)/remote"), true)
        checkThrows(try first.upload(source, to: target) { done, _ in if done >= 65536 { first.cancel() } })
        first.close()
        checkFalse(FileManager.default.fileExists(atPath: target))
        let second = try client(); defer { second.close() }
        var resumeOffset: UInt64?
        try second.upload(source, to: target) { done, _ in if resumeOffset == nil { resumeOffset = done } }
        checkGreaterThan(resumeOffset ?? 0, 0)
        checkEqual(try Data(contentsOf: URL(fileURLWithPath: target)), original)
        checkThrows(try second.upload(source, to: target) { _, _ in })
        checkEqual(try second.list(remote.path).map(\.name), [source.lastPathComponent])
        let destination = local.appendingPathComponent("download.bin")
        checkThrows(try second.download(target, to: destination) { done, _ in if done >= 65536 { second.cancel() } })
        second.close()
        checkFalse(FileManager.default.fileExists(atPath: destination.path))
        let otherHost = SFTPClient(executable: "/usr/libexec/sftp-server", arguments: ["-d", remote.path], resumeIdentity: "different server")
        try otherHost.connect()
        checkThrows(try otherHost.download(target, to: destination) { _, _ in })
        otherHost.close()
        let third = try client(); defer { third.close() }
        var downloadOffset: UInt64?
        try third.download(target, to: destination) { done, _ in if downloadOffset == nil { downloadOffset = done } }
        checkGreaterThan(downloadOffset ?? 0, 0)
        checkEqual(try Data(contentsOf: destination), original)
        let scpDestination = local.appendingPathComponent("scp-interrupted.bin")
        checkThrows(try third.download(target, to: scpDestination, initialTransfer: { _, partial in
            let handle = try FileHandle(forWritingTo: partial)
            try handle.write(contentsOf: original.prefix(65536)); try handle.close()
            throw ConfigurationError.invalid("Simulated SCP interruption")
        }) { _, _ in })
        let resumed = try client(); defer { resumed.close() }
        var scpOffset: UInt64?
        try resumed.download(target, to: scpDestination, initialTransfer: { _, _ in fail("SCP must not restart a partial download") }) {
            done, _ in if scpOffset == nil { scpOffset = done }
        }
        checkEqual(scpOffset, 65536)
        checkEqual(try Data(contentsOf: scpDestination), original)
        checkThrows(try third.list("/nonexistent-myterm-check-directory"))
        let mismatch = remote.appendingPathComponent("mismatch.bin").path
        checkThrows(try third.upload(source, to: mismatch) { done, _ in if done >= 65536 { third.cancel() } })
        third.close()
        try Data(repeating: 99, count: original.count).write(to: source)
        let fourth = try client(); defer { fourth.close() }
        checkThrows(try fourth.upload(source, to: mismatch) { _, _ in })
        checkFalse(FileManager.default.fileExists(atPath: mismatch))
    }
}
