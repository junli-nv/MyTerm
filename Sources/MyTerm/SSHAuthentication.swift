import AppKit
import MyTermCore

final class SSHAuthentication {
    private let memory: SSHPasswordMemory
    private let context: SSHLaunchContext
    private let label: String
    private weak var terminal: MouseTerminalView?
    private var channel: AskpassChannel?
    private var timer: Timer?
    private var alert: NSAlert?
    private var stopped = false
    private let report: (String) -> Void
    init(server: Server, context: SSHLaunchContext, terminal: MouseTerminalView, report: @escaping (String) -> Void) throws {
        self.memory = try SSHPasswordMemory(server: server)
        self.context = context; self.terminal = terminal; self.label = server.displayName; self.report = report
        channel = try AskpassChannel(path: context.directory.appendingPathComponent("auth").path) { [weak self] request, reply in
            DispatchQueue.main.async {
                guard let self, !self.stopped else { reply(nil); return }
                self.respond(request, reply: reply)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, FileManager.default.fileExists(atPath: self.context.controlPath) else { return }
            self.timer?.invalidate(); self.timer = nil
            do { try self.memory.authenticated() }
            catch { self.report("已登录，但密码保存失败：\(error.localizedDescription)") }
            self.channel?.stop(); self.channel = nil
        }
    }
    var environment: [String: String] {
        guard let channel else { return [:] }
        return ["SSH_ASKPASS": Bundle.main.executablePath ?? CommandLine.arguments[0], "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY": "myterm:0", "MYTERM_ASKPASS_SOCKET": channel.path, "MYTERM_ASKPASS_TOKEN": channel.token]
    }
    private func respond(_ request: AskpassRequest, reply: @escaping (String?) -> Void) {
        // Never infer authentication from terminal output: only the authenticated local askpass channel reaches here.
        let isConfirmation = request.hint == "confirm" || request.prompt.contains("(yes/no")
        let reusable = !isConfirmation && SSHPasswordMemory.isPassword(request.prompt)
        let retry = reusable && memory.wasAttempted(request.prompt)
        if reusable {
            do { if let password = try memory.cached(request.prompt) { reply(password); return } }
            catch { report(error.localizedDescription) }
        }
        guard let window = terminal?.window ?? NSApp.mainWindow else { reply(nil); return }
        let alert = NSAlert(); self.alert = alert
        alert.messageText = L10n.text(isConfirmation ? "确认 SSH 主机" : retry ? "请更新 SSH 密码" : "SSH 认证") + " · " + label
        alert.informativeText = (retry ? L10n.text("上次密码未被接受，请重新输入。") + "\n\n" : "") + request.prompt
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 34, width: 380, height: 24))
        let remember = NSButton(checkboxWithTitle: L10n.text("登录成功后记住密码（应用本地加密数据库）"), target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 380, height: 24); remember.state = .on
        if !isConfirmation {
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: reusable ? 62 : 28))
            if !reusable { field.frame.origin.y = 0 }
            view.addSubview(field); if reusable { view.addSubview(remember) }; alert.accessoryView = view
        }
        alert.addButton(withTitle: L10n.text(isConfirmation ? "信任并继续" : retry ? "更新并登录" : "继续"))
        alert.addButton(withTitle: L10n.text("取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { reply(nil); return }
            self.alert = nil
            guard !self.stopped, response == .alertFirstButtonReturn else { field.stringValue = ""; reply(nil); return }
            let value = isConfirmation ? "yes" : field.stringValue; field.stringValue = ""
            if reusable { self.memory.submitted(value, prompt: request.prompt, remember: remember.state == .on) }
            reply(value)
        }
        if !isConfirmation { alert.window.makeFirstResponder(field) }
    }
    func stop() {
        stopped = true; timer?.invalidate(); timer = nil
        if FileManager.default.fileExists(atPath: context.controlPath) {
            do { try memory.authenticated() } catch { report(error.localizedDescription) }
        }
        memory.discard()
        channel?.stop(); channel = nil
        if let alert, let parent = alert.window.sheetParent { parent.endSheet(alert.window, returnCode: .abort) }
        alert = nil
    }
    deinit { stop() }
}
