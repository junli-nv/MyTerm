import SwiftUI
import AppKit
import MyTermCore

final class SFTPModel: ObservableObject {
    @Published var entries: [RemoteEntry] = []
    @Published var path = "."
    @Published var pathInput = "."
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var connected = false
    @Published var status = "完成 SSH 登录后，点击连接 SFTP。"
    @Published var completed: UInt64 = 0
    @Published var total: UInt64 = 0
    @Published private(set) var transferFile = ""
    @Published private(set) var bytesPerSecond = 0.0
    @Published private(set) var showRate = false
    @Published private(set) var rateIsAverage = false
    @Published private(set) var transferDirection = ""
    private var rate = FileTransferRate()
    private var rateTimer: Timer?
    private let queue = DispatchQueue(label: "MyTerm.SFTP", qos: .userInitiated)
    private var client: SFTPClient?
    private var generation = UUID()
    private var pending = 0
    private var promising = false
    @Published private(set) var detached = false
    private var detachedWindow: SFTPWindowController?
    var selectedEntries: [RemoteEntry] { entries.filter { selected.contains($0.name) } }
    var connectionID: UUID { generation }
    var displayName: String { server.displayName }
    func showWindow() {
        if let detachedWindow { detachedWindow.showWindow(nil); detachedWindow.window?.makeKeyAndOrderFront(nil); return }
        detached = true
        let controller = SFTPWindowController(model: self)
        detachedWindow = controller; controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    func dock() { detachedWindow?.close(); windowClosed() }
    func windowClosed() { detachedWindow = nil; detached = false }

    private let server: Server
    private let context: SSHLaunchContext
    private var lastProgressTime = -Double.infinity
    private let clientFactory: (() throws -> SFTPClient)?
    init(server: Server, context: SSHLaunchContext, clientFactory: (() throws -> SFTPClient)? = nil) {
        self.server = server; self.context = context; self.clientFactory = clientFactory
    }

    func connect() {
        guard !busy, !connected else { return }
        // Never silently open an independent passwordless connection while terminal authentication is pending.
        guard clientFactory != nil || FileManager.default.fileExists(atPath: context.controlPath) else {
            status = "请先在左侧终端完成 SSH 登录，再连接 SFTP。"; return
        }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let identity = String(decoding: try encoder.encode(server), as: UTF8.self)
            let client = try clientFactory?() ?? SFTPClient(arguments: try server.sftpArguments(controlPath: context.controlPath, configPath: context.configPath), resumeIdentity: identity)
            generation = UUID(); self.client = client
            perform("连接 SFTP…", client: client) { try client.connect(); return try client.realpath(".") }
        } catch { status = error.localizedDescription }
    }
    func navigate(_ destination: String) {
        guard !busy, let client else { return }
        perform("读取目录…", client: client) { try client.realpath(destination) }
    }
    private func perform(_ message: String, client: SFTPClient, direction: String? = nil, completion: ((Error?) -> Void)? = nil, operation: @escaping () throws -> String) {
        pending += 1
        busy = true; status = message; completed = 0; total = 0
        rateTimer?.invalidate(); rateTimer = nil
        rate = FileTransferRate(); bytesPerSecond = 0; rateIsAverage = false
        showRate = direction != nil; transferDirection = direction ?? ""
        if direction != nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.bytesPerSecond = self.rate.sample(now: ProcessInfo.processInfo.systemUptime)
            }
            rateTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        queue.async { [weak self] in
            self?.lastProgressTime = -Double.infinity; self?.activeTransferPath = ""
            do {
                let path = try operation()
                let finished = ProcessInfo.processInfo.systemUptime
                let entries = try client.list(path)
                DispatchQueue.main.async {
                    guard let self, self.client === client else { completion?(CancellationError()); return }
                    self.path = path; self.pathInput = path; self.entries = entries; self.selected = self.selected.intersection(Set(entries.map(\.name)))
                    self.pending -= 1; self.busy = self.pending > 0
                    self.connected = true; self.status = "\(entries.count) 个项目"
                    if !self.busy { self.promising = false; self.finishRate(success: true, now: finished) }
                    completion?(nil)
                }
            } catch {
                client.close()
                DispatchQueue.main.async {
                    guard let self, self.client === client else { completion?(CancellationError()); return }
                    self.finishRate(success: false, now: ProcessInfo.processInfo.systemUptime)
                    self.client = nil; self.pending = 0; self.promising = false; self.busy = false; self.connected = false
                    self.status = error.localizedDescription
                    completion?(error)
                }
            }
        }
    }
    private func finishRate(success: Bool, now: TimeInterval) {
        rateTimer?.invalidate(); rateTimer = nil
        bytesPerSecond = success ? rate.average(now: now) : 0
        rateIsAverage = success && showRate
    }
    deinit { rateTimer?.invalidate() }
    func cancel() { disconnect() }
    func disconnect() {
        generation = UUID()
        finishRate(success: false, now: ProcessInfo.processInfo.systemUptime)
        showRate = false; transferFile = ""; busy = false; connected = false; pending = 0; promising = false
        selected.removeAll(); entries.removeAll(); status = "SFTP 已断开，SSH 会话保持连接。"
        let client = self.client; self.client = nil; client?.cancel()
        queue.async { client?.close() }
    }
    func stop() { disconnect(); dock() }
    func open(_ entry: RemoteEntry) {
        guard entry.isDirectory || entry.isLink else { return }
        if let target = try? SFTPClient.joining(path, entry.name) { navigate(target) }
    }
    func upload() {
        guard connected, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        if panel.urls.count == 1, let source = panel.urls.first {
            let alert = NSAlert(); alert.messageText = L10n.text("上传文件")
            alert.informativeText = L10n.text("远端文件名；再次使用相同文件和名称可断点续传。已有完整文件不会被覆盖。")
            let field = NSTextField(string: source.lastPathComponent)
            field.frame = NSRect(x: 0, y: 0, width: 350, height: 24); alert.accessoryView = field
            alert.addButton(withTitle: L10n.text("上传 / 续传")); alert.addButton(withTitle: L10n.text("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            alert.window.makeFirstResponder(nil)
            upload(panel.urls, remoteNames: [field.stringValue])
        } else { upload(panel.urls) }
    }
    func upload(_ sources: [URL], remoteNames: [String]? = nil) {
        guard connected, !busy, let client, !sources.isEmpty else { return }
        do {
            let names = remoteNames ?? sources.map(\.lastPathComponent)
            guard names.count == sources.count, Set(names).count == sources.count else {
                throw ConfigurationError.invalid("批量上传的文件或目录名称不能重复。")
            }
            let directory = path
            let targets = try names.map { try SFTPClient.joining(directory, $0) }
            perform("检查文件并准备上传…", client: client, direction: "上传") { [weak self] in
                for (source, target) in zip(sources, targets) {
                    self?.beginFile(source.lastPathComponent, client: client)
                    try client.uploadItem(source, to: target) { self?.treeProgress($0, $1, $2, client: client) }
                }
                return directory
            }
        } catch { status = error.localizedDescription }
    }
    func download() {
        let files = selectedEntries
        guard connected, !busy, !files.isEmpty else { return }
        if files.count == 1 && !files[0].isDirectory {
            let panel = NSSavePanel(); panel.nameFieldStringValue = files[0].name; panel.title = L10n.text("下载 / 续传")
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            download(files, destinations: [destination])
        } else {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            let destinations = files.map { directory.appendingPathComponent($0.name) }
            if destinations.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                let alert = NSAlert(); alert.messageText = L10n.text("下载目录已有同名项目，是否合并目录并覆盖不同的文件？")
                alert.addButton(withTitle: L10n.text("取消")); alert.addButton(withTitle: L10n.text("覆盖"))
                guard alert.runModal() == .alertSecondButtonReturn else { return }
            }
            download(files, destinations: destinations)
        }
    }
    func download(_ files: [RemoteEntry], destinations: [URL]) {
        guard connected, !busy, let client, !files.isEmpty, files.count == destinations.count else { return }
        do {
            let directory = path
            let remotes = try files.map { try SFTPClient.joining(directory, $0.name) }
            perform("准备下载…", client: client, direction: "下载") { [weak self] in
                for (remote, destination) in zip(remotes, destinations) {
                    self?.beginFile(destination.lastPathComponent, client: client)
                    try client.downloadItem(remote, to: destination) { self?.treeProgress($0, $1, $2, client: client) }
                }
                return directory
            }
        } catch { status = error.localizedDescription }
    }
    /// File promises carry a path and connection generation captured when dragging started.
    /// Serialize all promised files on the same SFTP queue; never reuse a reconnected session.
    func downloadPromise(remote: String, destination: URL, connectionID: UUID, completion: @escaping (Error?) -> Void) {
        guard connected, generation == connectionID, (!busy || promising), let client else {
            completion(ConfigurationError.invalid("SFTP 已断开或正在执行其他操作，请重新拖拽。")); return
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            completion(ConfigurationError.invalid("目标文件已存在，请选择其他名称。")); return
        }
        promising = true
        let directory = path
        perform("准备下载…", client: client, direction: "下载", completion: completion) { [weak self] in
            self?.beginFile(destination.lastPathComponent, client: client)
            try client.downloadItem(remote, to: destination) { self?.treeProgress($0, $1, $2, client: client) }
            return directory
        }
    }
    private var activeTransferPath = ""
    private func treeProgress(_ path: String, _ done: UInt64, _ total: UInt64, client: SFTPClient) {
        if activeTransferPath != path { activeTransferPath = path; beginFile(path, client: client) }
        progress(done, total, client: client)
    }
    private func beginFile(_ name: String, client: SFTPClient) {
        lastProgressTime = -Double.infinity
        DispatchQueue.main.async { [weak self] in
            guard let self, self.client === client else { return }
            self.transferFile = name; self.completed = 0; self.total = 0
            self.rate = FileTransferRate(); self.bytesPerSecond = 0; self.rateIsAverage = false
        }
    }
    private func progress(_ done: UInt64, _ total: UInt64, client: SFTPClient) {
        let now = ProcessInfo.processInfo.systemUptime
        guard done == total || now - lastProgressTime >= 0.1 else { return }
        lastProgressTime = now
        DispatchQueue.main.async { [weak self] in
            guard let self, self.client === client, self.busy, self.showRate else { return }
            if done < self.completed { self.rate = FileTransferRate() }
            self.rate.update(completed: done, now: now)
            self.completed = done; self.total = total
            self.status = "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: done), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file))"
        }
    }
}

