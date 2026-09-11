#if DEBUG
import AppKit
import SwiftUI
import MyTermCore

/// The integration fixture supplies a loopback SSH connection and its own tmux socket.
final class TmuxWindowCheck {
    private var session: TerminalSession?
    private var window: NSWindow?
    private var timer: Timer?
    private var phase = 0
    private var deadline = Date()
    private var settle = Date()
    private var grid = (0, 0)
    private var socket = ""
    private var tmux = ""
    private var didLogout = false
    private var lastPID: pid_t = 0
    private var completion: ((Result<Void, Error>) -> Void)?
    func run(fixture: String, completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        do {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fixture))) as! [String: Any]
            socket = json["socket"] as! String; tmux = json["tmux"] as! String
            let session = TerminalSession(label: "SSH / tmux 自检", executable: "/usr/bin/ssh", arguments: json["arguments"] as! [String])
            let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: TerminalPane(session: session))
            self.session = session; self.window = window
            window.makeKeyAndOrderFront(nil)
            deadline = Date().addingTimeInterval(45)
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [self] _ in tick() }
        } catch { finish(error.localizedDescription) }
    }
    private func control(_ args: [String]) -> String? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: tmux); process.arguments = ["-S", socket] + args
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        } catch { return nil }
    }
    private func tick() {
        guard let session, let window else { return }
        let terminal = session.terminal.getTerminal()
        if Date() > deadline { finish("SSH/tmux timeout phase \(phase): \(session.historySnapshot().text.suffix(1000))"); return }
        let text = session.historySnapshot().text
        switch phase {
        case 0:
            guard terminal.isCurrentBufferAlternate, control(["list-clients", "-F", "#{client_width} #{client_height}"]) != nil else { return }
            session.terminal.send(txt: "printf '\\033[31mMYTERM_%s 你好\\033[0m\\nTERM_IN=%s\\n' 'TMUX_RENDER' \"$TERM\"\n")
            phase = 1
        case 1:
            guard text.contains("MYTERM_TMUX_RENDER 你好"), text.contains("TERM_IN=screen") || text.contains("TERM_IN=tmux") else { return }
            guard control(["split-window", "-h", "-t", "check", "/bin/bash", "--noprofile", "--norc"]) != nil else { finish("tmux split failed"); return }
            session.terminal.send(txt: "printf 'SECOND_%s\\n' 'PANE_OK'\n")
            phase = 2
        case 2:
            guard text.contains("SECOND_PANE_OK"), text.contains("MYTERM_TMUX_RENDER") else { return }
            window.setContentSize(NSSize(width: 1080, height: 740)); settle = Date().addingTimeInterval(0.7); phase = 3
        case 3:
            guard Date() >= settle else { return }
            let expected = "\(terminal.cols) \(terminal.rows)"
            guard control(["list-clients", "-F", "#{client_width} #{client_height}"]) == expected else { return }
            grid = (terminal.cols, terminal.rows); session.sizeLocked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { window.setContentSize(NSSize(width: 780, height: 480)) }
            settle = Date().addingTimeInterval(0.8); phase = 4
        case 4:
            guard Date() >= settle else { return }
            guard grid == (terminal.cols, terminal.rows), control(["list-clients", "-F", "#{client_width} #{client_height}"]) == "\(grid.0) \(grid.1)" else {
                finish("SSH/tmux locked grid changed"); return
            }
            _ = control(["detach-client"]); phase = 5
        case 5:
            guard !terminal.isCurrentBufferAlternate else { return }
            print("PASS: real SSH/tmux Unicode/color rendering, split panes, resize, locked grid, alternate-screen exit")
            var args = session.arguments; args[args.count - 1] = "exec /bin/bash --noprofile --norc -i"
            session.stop()
            let next = TerminalSession(label: "SSH 重连自检", executable: "/usr/bin/ssh", arguments: args)
            next.onNormalExit = { [weak self] in self?.didLogout = true }
            self.session = next
            window.contentView = NSHostingView(rootView: TerminalPane(session: next))
            phase = 6
        case 6, 9, 12:
            guard session.isRunning, session.terminal.process.shellPid != lastPID else { return }
            session.terminal.send(txt: "printf 'RECONNECT_%s\\n' '\(phase)'\n")
            phase += 1
        case 7, 10:
            guard text.contains("RECONNECT_\(phase - 1)") else { return }
            lastPID = session.terminal.process.shellPid
            kill(lastPID, SIGKILL); phase += 1
        case 8, 11:
            guard session.canReconnect else { return }
            guard !didLogout else { finish("Unexpected logout on SSH interruption"); return }
            let key = phase == 8 ? "r" : "R"
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: key == "R" ? [.shift] : [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 15)!
            guard session.terminal.handleReconnectKey(event) else { finish("Reconnect key was not handled"); return }
            phase += 1
        case 13:
            guard text.contains("RECONNECT_12"), text.contains("RECONNECT_6") else { return }
            session.terminal.send(txt: "exit 7\n"); phase = 14
        default:
            guard didLogout else { return }
            guard !session.canReconnect else { finish("Normal logout incorrectly offers reconnect"); return }
            print("PASS: real SSH interruption, lowercase/uppercase R reconnect, retained history, normal exit callback")
            finish(nil)
        }
    }
    private func finish(_ error: String?) {
        timer?.invalidate(); timer = nil; session?.stop(); window?.close(); session = nil; window = nil
        let callback = completion; completion = nil
        callback?(error.map { .failure(ConfigurationError.invalid($0)) } ?? .success(()))
    }
}
#endif
