import Foundation
import MyTermCore
import CryptoKit

final class MemoryPasswordStore: PasswordStore {
    var values: [String: String] = [:]
    func read(_ account: String) throws -> String? { values[account] }
    func save(_ password: String, account: String) throws { values[account] = password }
    func delete(_ account: String) throws { values[account] = nil }
}
final class CredentialTests {
    func passwordLifecycle() throws {
        try configuredDestinationPasswords()
        try sharedJumpPasswords()
        let store = MemoryPasswordStore(), server = Server(host: "example.test", user: "dev", port: "22")
        let prompt = "dev@example.test's password: "
        let first = try SSHPasswordMemory(server: server, store: store)
        checkEqual(try first.cached(prompt), nil)
        first.submitted("first-test-value", prompt: prompt, remember: true)
        checkEqual(store.values.count, 0)
        try first.authenticated(); checkEqual(store.values.count, 1)
        let next = try SSHPasswordMemory(server: server, store: store)
        checkEqual(try next.cached(prompt), "first-test-value")
        checkEqual(try next.cached(prompt), nil)
        next.submitted("wrong-candidate", prompt: prompt, remember: true)
        checkEqual(try next.cached(prompt), nil)
        next.submitted("rotated-test-value", prompt: prompt, remember: true)
        try next.authenticated()
        checkEqual(try SSHPasswordMemory(server: server, store: store).cached(prompt), "rotated-test-value")
        var other = server; other.port = "2222"
        checkEqual(try SSHPasswordMemory(server: other, store: store).cached(prompt), nil)
        for challenge in ["Verification code:", "Password:", "Enter passphrase for key 'key':", "Are you sure (yes/no)?", "New password:"] {
            checkFalse(SSHPasswordMemory.isPassword(challenge))
            next.submitted("never-save-this", prompt: challenge, remember: true)
        }
        try next.authenticated(); checkEqual(store.values.count, 1)
        checkEqual(SSHPasswordMemory.isPassword("(dev@example.test) Password:"), true)
    }
    private func configuredDestinationPasswords() throws {
        let store = MemoryPasswordStore()
        let server = Server(host: "target.test", user: "dev")
        let account = try SSHPasswordMemory.destinationAccount(for: server)
        try store.save("configured-secret", account: account)
        let prompt = "dev@target.test's password:", alternate = "(dev@target.test) Password:"
        let memory = try SSHPasswordMemory(server: server, store: store)
        checkEqual(try memory.cached(prompt), "configured-secret")
        checkEqual(memory.wasAttempted(alternate), true)
        checkEqual(try memory.cached(alternate), nil)
        memory.submitted("replacement", prompt: alternate, remember: true)
        try memory.authenticated()
        checkEqual(try SSHPasswordMemory(server: server, store: store).cached(prompt), "replacement")
        checkEqual(store.values.count, 1)
        var keyed = server; keyed.authentication = .key
        checkEqual(try SSHPasswordMemory(server: keyed, store: store).cached(prompt), nil)
        var ambiguous = server
        ambiguous.jumpServers = [SSHJumpServer(host: server.host, user: server.user)]
        try store.save("never-offer-to-hop", account: SSHPasswordMemory.destinationAccount(for: ambiguous))
        checkEqual(try SSHPasswordMemory(server: ambiguous, store: store).cached(prompt), nil)
        checkEqual(try SSHPasswordMemory(server: server, store: store).cached("other@target.test's password:"), nil)
        checkEqual(try SSHPasswordMemory(server: server, store: store).cached("dev@other.test's password:"), nil)
        var resolved = server; resolved.jumpHost = "inherited-jump"
        checkEqual(try SSHPasswordMemory(server: resolved, credentialServer: server, store: store).cached(prompt), "replacement")
        // Cancelling or declining to remember a replacement must not store it.
        let cancelled = try SSHPasswordMemory(server: server, store: store)
        _ = try cancelled.cached(prompt); _ = try cancelled.cached(prompt)
        cancelled.submitted("not-remembered", prompt: prompt, remember: false)
        try cancelled.authenticated()
        checkEqual(try store.read(account), nil)
    }
    private func sharedJumpPasswords() throws {
        let store = MemoryPasswordStore()
        var first = Server(name: "A", host: "target-a", user: "target")
        first.jumpServers = [SSHJumpServer(host: "jump.test", user: "jump", authentication: .password)]
        var second = Server(name: "B", host: "target-b", user: "target")
        let preset = SSHJumpPreset.available(in: [first])[0]
        second.jumpServers = preset.copiedHops()
        checkFalse(second.jumpServers![0].id == first.jumpServers![0].id)
        let account = try SSHJumpCredentials.account(server: first, index: 0)
        checkEqual(try SSHJumpCredentials.account(server: second, index: 0), account)
        try store.save("fixture", account: account)
        let prompt = "jump@jump.test's password:"
        checkEqual(try SSHPasswordMemory(server: second, store: store).cached(prompt), "fixture")
        let retry = try SSHPasswordMemory(server: first, store: store)
        checkEqual(try retry.cached(prompt), "fixture")
        checkEqual(try retry.cached("(jump@jump.test) Password:"), nil)
        retry.submitted("updated", prompt: prompt, remember: true)
        try retry.authenticated()
        checkEqual(try SSHPasswordMemory(server: second, store: store).cached(prompt), "updated")
        for change in 0..<3 {
            var different = second
            if change == 0 { different.jumpServers?[0].port = "2222" }
            if change == 1 { different.jumpServers?[0].user = "other" }
            if change == 2 { different.jumpServers?.insert(SSHJumpServer(host: "outer", user: "jump"), at: 0) }
            checkFalse(try SSHJumpCredentials.account(server: different, index: change == 2 ? 1 : 0) == account)
        }
        var ambiguous = second
        ambiguous.jumpServers?.append(SSHJumpServer(host: "jump.test", port: "2222", user: "jump"))
        checkEqual(SSHJumpCredentials.matchingIndex(prompt: prompt, server: ambiguous), nil)
        checkEqual(try SSHPasswordMemory(server: ambiguous, store: store).cached(prompt), nil)
        var keyed = second; keyed.jumpServers?[0].authentication = .key
        checkEqual(try SSHPasswordMemory(server: keyed, store: store).cached(prompt), nil)
        let forgotten = try SSHPasswordMemory(server: first, store: store)
        forgotten.submitted("one-time", prompt: prompt, remember: false); try forgotten.authenticated()
        checkEqual(try store.read(account), "updated")
    }
    func configurationEdits() throws {
        let directory = URL(fileURLWithPath: "/tmp/credential-edit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLitePasswordStore(directory: directory)
        var jumpServer = Server(host: "destination", user: "target")
        jumpServer.jumpServers = [SSHJumpServer(host: "jump", user: "admin")]
        let jumpPrompt = "admin@jump's password:"
        let jumpLegacy = try SSHPasswordMemory.scopeIdentifier(for: jumpServer) + ":" + SHA256.hash(data: Data(jumpPrompt.utf8)).map { String(format: "%02x", $0) }.joined()
        try store.save("legacy-jump", account: jumpLegacy, label: "Legacy jump")
        try store.rename(jumpLegacy, name: "My jump")
        checkEqual(try SSHPasswordMemory(server: jumpServer, store: store).cached(jumpPrompt), "legacy-jump")
        let sharedJump = try SSHJumpCredentials.account(server: jumpServer, index: 0)
        checkEqual(try store.list().first(where: { $0.id == sharedJump })?.name, "My jump")
        checkEqual(try store.read(jumpLegacy), nil)
        try store.delete(sharedJump)
        var original = Server(name: "Before", host: "example.test", user: "dev", port: "22", identityFile: "/tmp/key")
        original.authentication = .password
        original.jumpServers = [SSHJumpServer(host: "bastion.test", user: "jump", identityFile: "/tmp/jump-key")]
        let prompt = "dev@example.test's password:"
        let suffix = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        let old = try SSHPasswordMemory.legacyScopeIdentifier(for: original) + ":" + suffix
        try store.save("saved-fixture", account: old, label: "Original label")
        try store.rename(old, name: "Named password")
        // Upgrade must migrate while the original configuration is still known.
        try SSHPasswordMemory.migrateLegacy(for: original, store: store)
        var edited = original
        edited.name = "After"; edited.compression = false; edited.debugLogging = true
        edited.historyLogging = .disabled; edited.x11Forwarding = .trusted
        edited.trzszEnabled = true; edited.identityFile = "/tmp/other-key"; edited.authentication = .automatic
        edited.jumpServers?[0].identityFile = "/tmp/other-jump-key"
        edited.jumpServers?[0].authentication = .password
        edited.forwards = [PortForward()]
        edited.proxy = NetworkProxy()
        checkEqual(try SSHPasswordMemory.scopeIdentifier(for: edited), try SSHPasswordMemory.scopeIdentifier(for: original))
        let login = try SSHPasswordMemory(server: edited, store: store)
        checkEqual(try login.cached(prompt), "saved-fixture")
        checkEqual(try store.read(old), nil)
        checkEqual(try store.list().first?.name, "Named password")
        checkEqual(try login.cached(prompt), nil) // Actual rejection prompts for replacement.
        login.submitted("replacement", prompt: prompt, remember: true); try login.authenticated()
        checkEqual(try SSHPasswordMemory(server: original, store: store).cached(prompt), "replacement")
        for field in 0..<5 {
            var different = edited
            switch field {
            case 0: different.host = "other.test"
            case 1: different.user = "other"
            case 2: different.port = "2222"
            case 3: different.jumpServers?[0].host = "other-bastion.test"
            default: different.id = UUID()
            }
            checkEqual(try SSHPasswordMemory(server: different, store: store).cached(prompt), nil)
        }
        // A stale legacy entry must not overwrite the newer credential.
        try store.save("stale", account: old, label: "Old")
        try SSHPasswordMemory.migrateLegacy(for: original, store: store)
        checkEqual(try SSHPasswordMemory(server: original, store: store).cached(prompt), "replacement")
        checkEqual(try store.list().first?.name, "Named password")
        var passwordOnly = original; passwordOnly.authentication = .password
        let passwordArgs = try passwordOnly.connectionArguments()
        checkFalse(passwordArgs.contains("-i"))
        checkEqual(passwordArgs.contains("PubkeyAuthentication=no"), true)
        // Key mode/path survive unrelated edits, validation and persistence unchanged.
        original.authentication = .key; original.jumpServers?[0].authentication = .key
        var keyEdited = original; keyEdited.name = "Key renamed"; keyEdited.compression = false
        let restored = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(keyEdited.validated()))
        checkEqual(restored.identityFile, original.identityFile)
        checkEqual(restored.jumpServers, original.jumpServers)
        let args = try restored.connectionArguments()
        checkEqual(args.contains("PreferredAuthentications=publickey"), true)
        checkEqual(args.contains("PasswordAuthentication=no"), true)
        checkEqual(args.contains(original.identityFile), true)
    }
    func channelRoundTrip() throws {
        let directory = URL(fileURLWithPath: "/tmp/auth-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let channel = try AskpassChannel(path: directory.appendingPathComponent("socket").path) { request, reply in
            if request.hint == "myterm-mcp" { reply(request.prompt) } else { reply(request.prompt == "fixture" ? "test-response" : nil) }
        }
        defer { channel.stop() }
        // Nested JSON escaping for a maximum-length command exceeds the old 64 KiB frame.
        let command = String(repeating: "\\\"\t", count: 10000)
        try CodexExecutionPolicy.validate(command, maximumBytes: 32768)
        let request = String(decoding: try JSONSerialization.data(withJSONObject: ["command": command]), as: UTF8.self)
        checkEqual(try AskpassChannel.answer(path: channel.path, token: channel.token, prompt: request, hint: "myterm-mcp"), request)
        checkEqual(try AskpassChannel.answer(path: channel.path, token: channel.token, prompt: "fixture", hint: nil), "test-response")
        checkEqual(try AskpassChannel.answer(path: channel.path, token: channel.token, prompt: "cancel", hint: nil), nil)
        checkThrows(try AskpassChannel.answer(path: channel.path, token: "invalid", prompt: "fixture", hint: nil))
    }
}

func realPasswordLogins(port: String, knownHosts: String, app: String) throws {
    let storage = URL(fileURLWithPath: "/tmp/myterm-password-db-\(UUID())")
    let store = SQLitePasswordStore(directory: storage)
    defer { try? FileManager.default.removeItem(at: storage) }
    var server = Server(host: "127.0.0.1", user: "fixture", port: port)
    server.authentication = .password
    let preset = ProcessInfo.processInfo.environment["MYTERM_PASSWORD_PRESET"] == "1"
    if preset { try store.save("fixture-before", account: SSHPasswordMemory.destinationAccount(for: server)) }
    var manualCounts: [Int] = []
    for phase in 0..<4 {
        // Exercise real OpenSSH cached authentication after unrelated config edits.
        server.name = "Edited fixture \(phase)"
        server.compression = phase % 2 == 0
        server.debugLogging = phase > 0
        let directory = URL(fileURLWithPath: "/tmp/pw-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = try SSHPasswordMemory(server: server, store: store)
        let lock = NSLock(); var manual = 0; var handlerError: Error?
        let channel = try AskpassChannel(path: directory.appendingPathComponent("auth").path) { request, reply in
            do {
                guard SSHPasswordMemory.isPassword(request.prompt) else { throw ConfigurationError.invalid("Unexpected SSH prompt in password fixture") }
                if let cached = try memory.cached(request.prompt) { reply(cached); return }
                lock.lock(); manual += 1; lock.unlock()
                let value = phase < 2 ? "fixture-before" : "fixture-after"
                memory.submitted(value, prompt: request.prompt, remember: true)
                reply(value)
            } catch { lock.lock(); handlerError = error; lock.unlock(); reply(nil) }
        }
        defer { channel.stop() }
        let process = Process(), output = Pipe(), errors = Pipe(), finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-T", "-F", "/dev/null", "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(knownHosts)"] + (try server.connectionArguments()) + ["--", server.host, "fixture"]
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = app; environment["SSH_ASKPASS_REQUIRE"] = "force"; environment["DISPLAY"] = "fixture:0"
        environment["MYTERM_ASKPASS_SOCKET"] = channel.path; environment["MYTERM_ASKPASS_TOKEN"] = channel.token
        process.environment = environment; process.standardInput = FileHandle.nullDevice
        let heldInput = Pipe()
        if environment["MYTERM_TRZSZ_CHECK"] == "1" {
            process.executableURL = URL(fileURLWithPath: app).deletingLastPathComponent().appendingPathComponent("trzsz")
            process.arguments = TrzszIntegration.arguments(sshArguments: process.arguments!)
            process.standardInput = heldInput
        }
        process.standardOutput = output; process.standardError = errors
        process.terminationHandler = { _ in finished.signal() }
        try process.run(); try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        guard finished.wait(timeout: .now() + 20) == .success else { process.terminate(); throw ConfigurationError.invalid("Password login fixture timed out") }
        lock.lock(); let failure = handlerError, count = manual; lock.unlock()
        if let failure { throw failure }
        guard process.terminationStatus == 0 else { throw ConfigurationError.invalid("Password login failed: \(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))") }
        let response = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        if environment["MYTERM_TRZSZ_CHECK"] == "1" {
            // The inner PTY merges SSH diagnostics with command output.
            guard response.contains("fixture-ok") else {
                throw ConfigurationError.invalid("Missing password fixture response: \(String(reflecting: response))")
            }
        } else { checkEqual(response, "fixture-ok\n") }
        try memory.authenticated(); manualCounts.append(count)
    }
    checkEqual(manualCounts, [preset ? 0 : 1, 0, 1, 0])
    print("PASS: real OpenSSH askpass + encrypted SQLite: first save, auto-login, rejected old password, update and auto-login")
}

func checkSQLitePasswords() throws {
    let directory = URL(fileURLWithPath: "/tmp/myterm-sqlite-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SQLitePasswordStore(directory: directory)
    let account = "account ' ; SELECT 中文"
    let password = "测试-password-'\"-unique-秘密"
    checkEqual(try store.read(account), nil)
    try store.save(password, account: account)
    checkEqual(try SQLitePasswordStore(directory: directory).read(account), password)
    checkEqual(try store.list().first?.name, nil)
    try store.rename(account, name: "生产环境 · 中文 ' 密码")
    checkEqual(try SQLitePasswordStore(directory: directory).list().first?.name, "生产环境 · 中文 ' 密码")
    checkEqual(try store.read(account), password)
    try store.save(password, account: account, label: "Updated prompt")
    checkEqual(try store.list().first?.displayName, "生产环境 · 中文 ' 密码")
    checkThrows(try store.rename(account, name: "bad\nname"))
    checkThrows(try store.rename(account, name: String(repeating: "名", count: 121)))
    checkThrows(try store.rename("missing", name: "Name"))
    try store.invalidateCachedPassword(account)
    checkEqual(try store.read(account), nil)
    checkEqual(try store.list().count, 0)
    try store.save(password, account: account, label: "Replacement prompt")
    checkEqual(try store.list().first?.name, "生产环境 · 中文 ' 密码")
    try store.rename(account, name: "   ")
    checkEqual(try store.list().first?.name, nil)
    checkEqual(try store.list().first?.displayName, "Replacement prompt")
    try store.rename(account, name: "Delete me")
    try store.delete(account)
    try store.save(password, account: account)
    checkEqual(try store.list().first?.name, nil)
    let database = directory.appendingPathComponent("passwords.sqlite")
    let keyFile = directory.appendingPathComponent("encryption.key")
    checkFalse(try Data(contentsOf: database).range(of: Data(password.utf8)) != nil)
    for url in [database, keyFile] {
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        checkEqual(permissions.intValue & 0o777, 0o600)
    }
    let key = try Data(contentsOf: keyFile), before = try Data(contentsOf: database)
    try Data(repeating: 0, count: 32).write(to: keyFile)
    checkThrows(try store.read(account))
    checkEqual(try Data(contentsOf: database), before)
    try FileManager.default.removeItem(at: keyFile)
    checkThrows(try store.read(account))
    checkFalse(FileManager.default.fileExists(atPath: keyFile.path))
    try key.write(to: keyFile)
    try store.save("updated", account: account)
    checkEqual(try store.read(account), "updated")
    try store.save("other", account: "other")
    try store.delete(account); checkEqual(try store.read(account), nil)
    checkEqual(try store.read("other"), "other")
    try store.deleteAll(); checkEqual(try store.read("other"), nil)
}
