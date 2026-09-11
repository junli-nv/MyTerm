import AppKit
import SwiftUI
import SwiftTerm
import MyTermCore
import Combine

final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let startedAt = Date()
    @Published var label: String
    let executable: String
    private(set) var arguments: [String]
    private(set) var server: Server?
    private(set) var connectionContext: SSHLaunchContext?
    @Published private(set) var sftp: SFTPModel?
    @Published var showSFTP = false
    @Published var statusBarVisible = false
    @Published var sizeLocked = false
    @Published var encoding: TerminalEncoding = .utf8 {
        didSet {
            do { try terminal.setEncoding(encoding) }
            catch { status = error.localizedDescription }
        }
    }
    var directory: String
    let terminal = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
    @Published var status = "准备启动"
    @Published var isRunning = false
    @Published private(set) var canReconnect = false
    var onNormalExit: (() -> Void)?
    private let configuredServer: Server?
    var sourceServer: Server? { configuredServer ?? server }
    private var started = false
    private var stopped = false
    private var themeSubscription: AnyCancellable?
    private var authentication: SSHAuthentication?

    init(label: String, executable: String, arguments: [String], server: Server? = nil, context: SSHLaunchContext? = nil, directory: String? = nil) {
        self.label = label
        self.executable = executable
        self.arguments = arguments
        self.server = server
        self.configuredServer = server
        self.connectionContext = context
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        if let server, let context { sftp = SFTPModel(server: server, context: context) } else { sftp = nil }
        super.init()
        terminal.processDelegate = self
        terminal.getTerminal().changeScrollback(50_000)
        if server != nil {
            terminal.zmodem = ZmodemBridge(terminal: terminal)
            terminal.registerForDraggedTypes([.fileURL])
            terminal.canUploadFiles = { [weak self] in
                guard let self, self.isRunning, let path = self.connectionContext?.controlPath else { return false }
                return FileManager.default.fileExists(atPath: path)
            }
        }
        ThemePreferences.shared.apply(to: terminal)
        themeSubscription = ThemePreferences.shared.$theme.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }; ThemePreferences.shared.apply(to: self.terminal)
        }
    }

    func start() {
        guard !started, !stopped else { return }
        started = true
        if executable == "/usr/bin/ssh", connectionContext == nil, let server {
            status = "准备 SSH 连接…"
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let resolved = try SSHConfigurationResolver.resolvingJump(server)
                    let context = try SSHLaunchContext(server: resolved)
                    let args = try resolved.sshArguments(controlPath: context.controlPath, configPath: context.configPath)
                    DispatchQueue.main.async {
                        guard let self, !self.stopped else { return }
                        self.server = resolved; self.connectionContext = context; self.arguments = args
                        self.sftp = SFTPModel(server: resolved, context: context)
                        self.launch()
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let self, !self.stopped else { return }
                        self.connectionFailed(error.localizedDescription)
                    }
                }
            }
        } else { launch() }
    }

    func historySnapshot() -> SessionHistory {
        let emulator = terminal.getTerminal()
        var text = String(decoding: emulator.getBufferAsData(kind: .normal), as: UTF8.self)
        if emulator.isCurrentBufferAlternate {
            text += "\n[全屏程序当前画面]\n" + String(decoding: emulator.getBufferAsData(kind: .alt), as: UTF8.self)
        }
        // SwiftTerm exports the continuation cell of wide characters as NUL.
        // It is a grid placeholder, not part of the user's text.
        return SessionHistory(id: id, label: label, started: startedAt, text: text.replacingOccurrences(of: "\0", with: ""))
    }

    private func launch() {
        var environment = ProcessInfo.processInfo.environment
        if let mode = server?.x11Forwarding, mode != .disabled {
            if environment["DISPLAY", default: ""].isEmpty {
                let process = Process(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = ["getenv", "DISPLAY"]
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                if (try? process.run()) != nil {
                    let display = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    process.waitUntilExit()
                    if !display.isEmpty { environment["DISPLAY"] = display }
                }
            }
            guard !environment["DISPLAY", default: ""].isEmpty else {
                connectionFailed("未检测到 X11 DISPLAY，请安装并启动 XQuartz 后重新连接，或关闭 X11 转发。"); return
            }
        }
        if executable == "/usr/bin/ssh", let server, let context = connectionContext {
            do {
                authentication = try SSHAuthentication(server: server, context: context, terminal: terminal) { [weak self] message in self?.status = message }
                environment.merge(authentication!.environment) { _, value in value }
            } catch { connectionFailed(error.localizedDescription); return }
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "MyTerm"
        environment["SHELL"] = "/bin/bash"
        environment["BASH_SILENCE_DEPRECATION_WARNING"] = "1"
        // A new PTY owns its size and is not a client of the launching shell's tmux.
        for key in ["LINES", "COLUMNS", "TMUX", "TMUX_PANE", "STY"] { environment.removeValue(forKey: key) }
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        var launchExecutable = executable, launchArguments = arguments
        terminal.trzszEnabled = false
        terminal.dragUploadProtocol = server?.dragUploadProtocol ?? .automatic
        if executable == "/usr/bin/ssh", server?.trzszEnabled ?? true {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/trzsz").path
            guard FileManager.default.isExecutableFile(atPath: helper) else {
                connectionFailed("trzsz 客户端缺失，请重新安装 MyTerm 或关闭该连接的 trzsz 支持。"); return
            }
            launchExecutable = helper; launchArguments = TrzszIntegration.arguments(sshArguments: arguments)
            terminal.trzszEnabled = true
        }
        terminal.startProcess(executable: launchExecutable, args: launchArguments,
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: directory)
        isRunning = terminal.process.running
        status = isRunning ? (executable == "/usr/bin/ssh" ? "SSH 进程运行中" : "Bash") : "启动失败"
        if !isRunning, executable == "/usr/bin/ssh" { connectionFailed("SSH 启动失败") }
    }

    private func connectionFailed(_ message: String) {
        guard !stopped else { return }
        canReconnect = true
        status = "\(message) · 按 R 重新连接"
        terminal.reconnectHandler = { [weak self] in self?.reconnect() }
    }

    func reconnect() {
        guard canReconnect, !stopped, !terminal.process.running else { return }
        canReconnect = false; terminal.reconnectHandler = nil
        authentication?.stop(); authentication = nil; sftp?.stop(); sftp = nil
        terminal.zmodem?.cancel()
        connectionContext = nil; server = configuredServer
        try? terminal.setEncoding(encoding)
        // Preserve normal scrollback while leaving a disconnected full-screen program.
        if terminal.getTerminal().isCurrentBufferAlternate {
            terminal.feed(text: "\u{1b}[?1049l")
        }
        terminal.feed(text: "\u{1b}[0m\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1003l\u{1b}[?1006l\u{1b}[?2004l\r\n[正在重新连接 SSH…]\r\n")
        started = false; start()
    }

    func stop() {
        stopped = true
        canReconnect = false; terminal.reconnectHandler = nil
        authentication?.stop(); authentication = nil
        sftp?.stop()
        terminal.zmodem?.cancel()
        guard started else { return }
        if terminal.process.running {
            let pid = terminal.process.shellPid
            // Interactive Bash ignores SIGTERM. Hang up its terminal session first.
            let foreground = tcgetpgrp(terminal.process.childfd)
            if foreground > 0, getsid(foreground) == pid { kill(-foreground, SIGHUP) }
            if pid > 0 { kill(pid, SIGHUP) }
            terminal.terminate()
            ChildProcessCleanup.reap(pid)
        }
        isRunning = false
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard server == nil, let directory, let url = URL(string: directory), url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        self.directory = url.path
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.isRunning = false
            self.authentication?.stop(); self.authentication = nil
            self.sftp?.stop(); self.sftp = nil
            guard self.executable == "/usr/bin/ssh" else {
                self.status = "会话已结束"
                if let status = exitCode, status & 0x7f == 0 { self.onNormalExit?() }
                return
            }
            self.terminal.zmodem?.cancel()
            // SwiftTerm 1.20's forkpty backend passes raw waitpid status, not an exit code.
            if let status = exitCode, status & 0x7f == 0, (status >> 8) & 0xff != 255 {
                self.status = "SSH 已退出"; self.onNormalExit?()
            } else {
                self.connectionFailed("SSH 连接已断开")
                self.terminal.feed(text: "\r\n[SSH 连接已断开，按 R 重新连接]\r\n")
            }
        }
    }
}

struct TerminalSurface: NSViewRepresentable {
    @ObservedObject var session: TerminalSession

    func makeNSView(context: Context) -> TerminalContainer {
        TerminalContainer(session: session)
    }

    func updateNSView(_ container: TerminalContainer, context: Context) {
        container.configure(session)
    }
}

/// Keeps SwiftUI's transient zero-sized layouts away from the PTY. Dimensions use
/// AppKit points, so backing-scale changes do not multiply the terminal grid.
final class TerminalContainer: NSView {
    private let scroll = NSScrollView()
    private var session: TerminalSession
    private var pending: DispatchWorkItem?
    private var focusOnAttach = true
    init(session: TerminalSession) {
        self.session = session
        super.init(frame: .zero)
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        addSubview(scroll)
        configure(session)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ session: TerminalSession) {
        self.session = session
        if scroll.documentView !== session.terminal {
            focusOnAttach = true
            session.terminal.removeFromSuperview()
            session.terminal.autoresizingMask = []
            scroll.documentView = session.terminal
        }
        scroll.hasHorizontalScroller = session.sizeLocked
        scroll.hasVerticalScroller = session.sizeLocked
        needsLayout = true
        scheduleSize()
    }
    override func layout() {
        super.layout()
        scroll.frame = bounds
        scheduleSize()
    }
    private func scheduleSize() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applySize() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func applySize() {
        guard window != nil, scroll.documentView === session.terminal,
              bounds.width >= 160, bounds.height >= 80 else { return }
        if !session.sizeLocked {
            let size = scroll.contentSize
            if session.terminal.frame.size != size { session.terminal.setFrameSize(size) }
            scroll.contentView.scroll(to: .zero)
        }
        session.start()
        if focusOnAttach { window?.makeFirstResponder(session.terminal); focusOnAttach = false }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { needsLayout = true }
    }
}
