import Foundation
import MyTermCore

final class MemoryPasswordStore: PasswordStore {
    var values: [String: String] = [:]
    func read(_ account: String) throws -> String? { values[account] }
    func save(_ password: String, account: String) throws { values[account] = password }
    func delete(_ account: String) throws { values[account] = nil }
}
final class CredentialTests {
    func passwordLifecycle() throws {
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
    func channelRoundTrip() throws {
        let directory = URL(fileURLWithPath: "/tmp/auth-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let channel = try AskpassChannel(path: directory.appendingPathComponent("socket").path) { request, reply in
            reply(request.prompt == "fixture" ? "test-response" : nil)
        }
        defer { channel.stop() }
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
    var manualCounts: [Int] = []
    for phase in 0..<4 {
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
    checkEqual(manualCounts, [1, 0, 1, 0])
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
