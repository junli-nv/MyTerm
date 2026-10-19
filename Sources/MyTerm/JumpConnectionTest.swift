import AppKit
import SwiftTerm
import MyTermCore

final class JumpConnectionTest: ObservableObject, LocalProcessDelegate {
    @Published private(set) var running = false
    @Published private(set) var result = ""
    private(set) var succeeded = false
    private var process: LocalProcess?
    private var context: SSHLaunchContext?
    private var authentication: SSHAuthentication?
    private let terminal = MouseTerminalView(frame: .zero)
    private var timer: Timer?
    private var readinessTimer: Timer?
    private var output = Data()
    func start(_ probe: SSHJumpProbe, configPath: String? = nil, store: PasswordStore = SQLitePasswordStore(), password: String = "") {
        cancel(); succeeded = false
        do {
            let context = try SSHLaunchContext(server: probe.server, userConfig: configPath ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config").path)
            var testStore: PasswordStore = store
            if !password.isEmpty, probe.server.authentication != .key {
                guard let account = probe.passwordAccount else { throw ConfigurationError.invalid("保存跳板机密码前请填写用户名。") }
                testStore = JumpTestPasswordStore(base: store, account: account, password: password)
            }
            let auth = try SSHAuthentication(server: probe.server, destinationPasswordAccount: probe.passwordAccount, store: testStore, context: context, terminal: terminal) { [weak self] message in self?.result = message }
            self.context = context; authentication = auth
            var environment = ProcessInfo.processInfo.environment
            environment.merge(auth.environment) { _, value in value }
            let process = LocalProcess(delegate: self); self.process = process
            output = Data(); result = L10n.text("正在测试 SSH 连接与认证（最多 45 秒）…"); running = true
            process.startProcess(executable: "/usr/bin/ssh", args: try probe.arguments(configPath: context.configPath ?? configPath, controlPath: context.controlPath), environment: environment.map { "\($0.key)=\($0.value)" })
            guard running else { return }
            // OpenSSH creates this private mux socket only after authentication.
            // No shell, PTY, exec or forwarding request is required on the server.
            readinessTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, self.running,
                      FileManager.default.fileExists(atPath: context.controlPath) else { return }
                do {
                    try self.authentication?.confirmAuthenticated()
                    self.succeeded = true
                    self.finish(L10n.text("测试成功：SSH 连接与认证通过；未测试向后续目标转发。"))
                } catch { self.finish(L10n.text("SSH 测试成功，但保存密码失败：") + error.localizedDescription) }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
                self?.cancel(); self?.result = L10n.text("测试超时，请检查网络、路径或认证提示。")
            }
        } catch { finish(L10n.text("测试失败：") + error.localizedDescription) }
    }
    func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0) }
    func dataReceived(slice: ArraySlice<UInt8>) {
        output.append(contentsOf: slice)
        if output.count > 8192 { output = output.suffix(8192) }
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        guard source === process, running else { return }
        let transcript = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        finish(L10n.text("测试失败：") + "\n" + transcript + "\n(exit=\(exitCode.map(String.init) ?? "unknown"))")
    }

    private func finish(_ message: String) {
        running = false; timer?.invalidate(); timer = nil
        readinessTimer?.invalidate(); readinessTimer = nil
        authentication?.stop(); authentication = nil
        if let process, process.shellPid > 0 {
            let pid = process.shellPid
            let foreground = tcgetpgrp(process.childfd)
            if foreground > 0, getsid(foreground) == pid { kill(-foreground, SIGHUP) }
            kill(pid, SIGHUP); process.terminate(); ChildProcessCleanup.reap(pid)
        }
        process = nil; context = nil; result = message
    }
    func cancel() {
        guard running else { return }
        finish(L10n.text("测试已取消。"))
    }
    func reset() { cancel(); result = ""; succeeded = false }
    deinit { readinessTimer?.invalidate(); timer?.invalidate(); authentication?.stop() }
}
