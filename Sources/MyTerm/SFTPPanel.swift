import SwiftUI
import AppKit
import MyTermCore

final class SFTPModel: ObservableObject {
    @Published var entries: [RemoteEntry] = []
    @Published var path = "."
    @Published var pathInput = "."
    @Published var selected: String?
    @Published var busy = false
    @Published var connected = false
    @Published var status = "完成 SSH 登录后，点击连接 SFTP。"
    @Published var completed: UInt64 = 0
    @Published var total: UInt64 = 0
    @Published var useSCP = false
    @Published private(set) var bytesPerSecond = 0.0
    @Published private(set) var showRate = false
    @Published private(set) var rateIsAverage = false
    @Published private(set) var transferDirection = ""
    private var rate = FileTransferRate()
    private var rateTimer: Timer?
    private var scp: SCPTransfer?
    private let queue = DispatchQueue(label: "MyTerm.SFTP", qos: .userInitiated)
    private var client: SFTPClient?
    private let server: Server
    private let context: SSHLaunchContext
    private var lastProgressTime = -Double.infinity
    init(server: Server, context: SSHLaunchContext) { self.server = server; self.context = context }

    func connect() {
        guard !busy else { return }
        // Never silently open an independent passwordless connection while terminal authentication is pending.
        guard FileManager.default.fileExists(atPath: context.controlPath) else {
            status = "请先在左侧终端完成 SSH 登录，再连接 SFTP。"; return
        }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let identity = String(decoding: try encoder.encode(server), as: UTF8.self)
            let client = SFTPClient(arguments: try server.sftpArguments(controlPath: context.controlPath, configPath: context.configPath), resumeIdentity: identity)
            self.client = client
            perform("连接 SFTP…", client: client) { try client.connect(); return try client.realpath(".") }
        } catch { status = error.localizedDescription }
    }
    func navigate(_ destination: String) {
        guard !busy, let client else { return }
        perform("读取目录…", client: client) { try client.realpath(destination) }
    }
    private func perform(_ message: String, client: SFTPClient, direction: String? = nil, operation: @escaping () throws -> String) {
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
            self?.lastProgressTime = -Double.infinity
            do {
                let path = try operation()
                let finished = ProcessInfo.processInfo.systemUptime
                let entries = try client.list(path)
                DispatchQueue.main.async {
                    guard let self, self.client === client else { return }
                    self.finishRate(success: true, now: finished)
                    self.path = path; self.pathInput = path; self.entries = entries; self.selected = nil
                    self.connected = true; self.busy = false; self.status = "\(entries.count) 个项目"
                }
            } catch {
                client.close()
                DispatchQueue.main.async {
                    guard let self, self.client === client else { return }
                    self.finishRate(success: false, now: ProcessInfo.processInfo.systemUptime)
                    self.client = nil; self.busy = false; self.connected = false
                    self.status = error.localizedDescription
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
    func cancel() { scp?.cancel(); client?.cancel(); status = "正在取消，保留续传文件…" }
    func stop() {
        finishRate(success: false, now: ProcessInfo.processInfo.systemUptime)
        showRate = false; busy = false
        scp?.cancel()
        let client = self.client; self.client = nil; client?.cancel()
        queue.async { client?.close() }
    }
    func open(_ entry: RemoteEntry) {
        guard entry.isDirectory || entry.isLink else { return }
        if let target = try? SFTPClient.joining(path, entry.name) { navigate(target) }
    }
    func upload() {
        guard !busy, let client else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("上传文件"); alert.informativeText = L10n.text("远端文件名；再次使用相同文件和名称可断点续传。已有完整文件不会被覆盖。")
        let name = NSTextField(string: source.lastPathComponent); name.frame = NSRect(x: 0, y: 0, width: 350, height: 24)
        alert.accessoryView = name; alert.addButton(withTitle: L10n.text("上传 / 续传")); alert.addButton(withTitle: L10n.text("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let target = try SFTPClient.joining(path, name.stringValue), directory = path
            let transfer = useSCP ? SCPTransfer(server: server, controlPath: context.controlPath, configPath: context.configPath) : nil
            scp = transfer
            let initial: ((URL, String) throws -> Void)? = transfer.map { runner in { [weak self] source, remote in
                let size = UInt64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                try runner.transfer(local: source, remote: remote, upload: true) {
                    if let done = try? client.stat(remote).size { self?.progress(done, size) }
                }
            } }
            perform("检查文件并准备上传…", client: client, direction: "上传") { [weak self] in
                try client.upload(source, to: target, initialTransfer: initial) { self?.progress($0, $1) }; return directory
            }
        } catch { status = error.localizedDescription }
    }
    func download() {
        guard !busy, let client, let selected, let entry = entries.first(where: { $0.name == selected }), !entry.isDirectory else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = selected; panel.title = L10n.text("下载 / 续传")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let remote = try SFTPClient.joining(path, selected), directory = path
            let transfer = useSCP ? SCPTransfer(server: server, controlPath: context.controlPath, configPath: context.configPath) : nil
            scp = transfer
            let initial: ((String, URL) throws -> Void)? = transfer.map { runner in { [weak self] remote, local in
                let size = try client.stat(remote).size ?? 0
                try runner.transfer(local: local, remote: remote, upload: false) {
                    if let done = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize { self?.progress(UInt64(done), size) }
                }
            } }
            perform("准备下载…", client: client, direction: "下载") { [weak self] in
                try client.download(remote, to: destination, initialTransfer: initial) { self?.progress($0, $1) }; return directory
            }
        } catch { status = error.localizedDescription }
    }
    private func progress(_ done: UInt64, _ total: UInt64) {
        let now = ProcessInfo.processInfo.systemUptime
        guard done == total || now - lastProgressTime >= 0.1 else { return }
        lastProgressTime = now
        DispatchQueue.main.async { [weak self] in
            guard let self, self.busy, self.showRate else { return }
            self.rate.update(completed: done, now: now)
            self.completed = done; self.total = total
            self.status = "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: done), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file))"
        }
    }
}

struct SFTPPanel: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var model: SFTPModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("SFTP 文件", systemImage: "folder.badge.gearshape").font(.headline)
                Spacer()
                if model.connected { Button { model.navigate(model.path) } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy) }
                else { Button("连接", action: model.connect).disabled(model.busy) }
            }
            HStack {
                Button { model.navigate(model.path == "/" ? "/" : model.path + "/..") } label: { Image(systemName: "arrow.up") }
                TextField("远端目录", text: $model.pathInput).onSubmit { model.navigate(model.pathInput) }
            }.disabled(!model.connected || model.busy)
            HStack {
                Button("上传 / 续传…", action: model.upload)
                Button("下载 / 续传…", action: model.download).disabled(model.selected == nil || model.entries.first(where: { $0.name == model.selected })?.isDirectory == true)
            }.disabled(!model.connected || model.busy)
            Toggle("使用 SCP（断点续传使用 SFTP）", isOn: $model.useSCP).font(.caption).disabled(model.busy)
            List(selection: $model.selected) {
                ForEach(model.entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : entry.isLink ? "link" : "doc")
                            .foregroundStyle(entry.isDirectory ? .mint : .secondary)
                        Text(entry.name).lineLimit(1).help(entry.name)
                        Spacer()
                        if let size = entry.size, !entry.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(entry.name).contentShape(Rectangle()).onTapGesture(count: 2) { model.open(entry) }
                }
            }.disabled(model.busy)
            if model.busy {
                HStack {
                    if model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
                    else { ProgressView().controlSize(.small) }
                    Button("取消", action: model.cancel)
                }
            }
            Text(L10n.text(model.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
            if model.showRate {
                Text("\(L10n.text(model.transferDirection)) \(L10n.text(model.rateIsAverage ? "平均速度" : "速度")): \(ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, model.bytesPerSecond))), countStyle: .file))/s")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("按文件已传输字节计算；断点续传不包含此前已完成的部分。SCP 通过临时文件大小采样。")
            }
        }.padding(12).frame(minWidth: 310, idealWidth: 350, maxWidth: 520)
    }
}
