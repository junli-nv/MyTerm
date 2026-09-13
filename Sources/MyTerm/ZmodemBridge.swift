import AppKit
import MyTermCore

final class ZmodemBridge: ObservableObject {
    var testSelection: ((Bool) -> [URL])?
    @Published var active = false
    @Published var awaitingReceiver = false
    private var droppedURLs: [URL]?
    private var receiverTimeout: DispatchWorkItem?
    @Published var status = ""
    @Published private(set) var bytesPerSecond = 0.0
    @Published private(set) var transferredBytes: UInt64 = 0
    @Published private(set) var receiving = false
    @Published private(set) var rateIsAverage = false
    private var rateMeter: ZmodemRateMeter?
    private var rateTimer: Timer?
    private func startRate(receiving: Bool) {
        rateTimer?.invalidate()
        self.receiving = receiving; bytesPerSecond = 0; transferredBytes = 0; rateIsAverage = false
        rateMeter = ZmodemRateMeter(now: ProcessInfo.processInfo.systemUptime)
        rateTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bytesPerSecond = self.rateMeter?.sample(now: ProcessInfo.processInfo.systemUptime) ?? 0
            self.transferredBytes = self.rateMeter?.bytes ?? 0
        }
        RunLoop.main.add(rateTimer!, forMode: .common)
    }
    private func finishRate(completed: Bool) {
        rateTimer?.invalidate(); rateTimer = nil
        transferredBytes = rateMeter?.bytes ?? 0
        bytesPerSecond = completed ? rateMeter?.average(now: ProcessInfo.processInfo.systemUptime) ?? 0 : 0
        rateIsAverage = completed; rateMeter = nil
    }
    deinit { rateTimer?.invalidate() }
    private var detector = ZmodemDetector()
    private var pending = Data()
    private var helper: Process?
    private var stdin: FileHandle?
    private var panel: NSOpenPanel?
    private let writer = DispatchQueue(label: "MyTerm.Zmodem.Write")
    private var queuedBytes = 0
    private weak var terminal: MouseTerminalView?
    init(terminal: MouseTerminalView) { self.terminal = terminal }

    @discardableResult func uploadDroppedFiles(_ urls: [URL]) -> Bool {
        guard !active, !awaitingReceiver, !urls.isEmpty, let terminal,
              !terminal.getTerminal().isCurrentBufferAlternate else {
            status = "请回到 SSH shell 提示符，并等待当前传输结束后再拖入文件。"; return false
        }
        guard urls.allSatisfy({ $0.isFileURL && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && FileManager.default.isReadableFile(atPath: $0.path) }) else {
            status = "Zmodem 拖拽上传仅支持可读取的普通文件。"; return false
        }
        guard ["/opt/homebrew/bin/lsz", "/usr/local/bin/lsz", "/usr/bin/sz"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            status = "未找到 lrzsz，请先安装：brew install lrzsz"; return false
        }
        bytesPerSecond = 0; transferredBytes = 0; rateIsAverage = false; receiving = false
        droppedURLs = urls; awaitingReceiver = true; status = "正在启动远端 rz，等待 Zmodem 握手…"
        // Clear an unfinished command line before starting the explicitly requested transfer.
        terminal.process.send(data: Array("\u{15}rz\r".utf8)[...])
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingReceiver else { return }
            self.cancel(); self.status = "未收到 rz 响应；请确认远端已安装 lrzsz，并停留在 shell 提示符。"
        }
        receiverTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        return true
    }

    func consume(_ data: Data) -> Data {
        if active {
            if receiving { rateMeter?.add(data.count) }
            if let stdin { write(data, to: stdin) }
            else {
                pending.append(data)
                if pending.count > 2 * 1024 * 1024 { cancel(); status = "Zmodem 握手缓存过大，已取消。" }
            }
            return Data()
        }
        let result = detector.feed(data)
        if let handshake = result.handshake {
            receiving = result.receiving
            bytesPerSecond = 0; transferredBytes = 0; rateIsAverage = false
            active = true; pending = handshake; status = result.receiving ? "选择 Zmodem 接收目录…" : "选择 Zmodem 发送文件…"
            choose(receiving: result.receiving)
        }
        return result.visible
    }
    private func choose(receiving: Bool) {
        if let urls = droppedURLs {
            droppedURLs = nil; awaitingReceiver = false; receiverTimeout?.cancel(); receiverTimeout = nil
            guard !receiving else { cancel(); status = "远端发起了接收方向相反的传输，请重试。"; return }
            start(receiving: false, urls: urls); return
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test"), let testSelection {
            let urls = testSelection(receiving)
            DispatchQueue.main.async { [weak self] in self?.start(receiving: receiving, urls: urls) }
            return
        }
        guard let window = terminal?.window else { cancel(); return }
        let panel = NSOpenPanel(); self.panel = panel
        panel.title = receiving ? "Zmodem 接收目录" : "Zmodem 发送文件"
        panel.canChooseDirectories = receiving; panel.canChooseFiles = !receiving
        panel.canCreateDirectories = receiving; panel.allowsMultipleSelection = !receiving
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.active else { return }
            self.panel = nil
            guard response == .OK, !panel.urls.isEmpty else { self.cancel(); return }
            self.start(receiving: receiving, urls: panel.urls)
        }
    }
    private func start(receiving: Bool, urls: [URL]) {
        let names = receiving ? ["lrz", "rz"] : ["lsz", "sz"]
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].flatMap { base in names.map { base + "/" + $0 } }
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            cancel(); status = "未找到 lrzsz。请安装后重试：brew install lrzsz"; return
        }
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = receiving ? urls[0] : urls[0].deletingLastPathComponent()
        process.arguments = receiving ? ["--binary", "--escape", "--restricted", "--protect"]
            : ["--binary", "--escape", "--resume", "--"] + urls.map(\.path)
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        do {
            try process.run(); helper = process; stdin = input.fileHandleForWriting
            try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            status = receiving ? "Zmodem 正在接收…" : "Zmodem 正在发送…"
            startRate(receiving: receiving)
            let buffered = pending; pending = Data(); write(buffered, to: input.fileHandleForWriting)
            if receiving { rateMeter?.add(buffered.count) }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // Protocol replies can be just a few bytes; forward each pipe read immediately.
                var buffer = [UInt8](repeating: 0, count: 32768)
                while true {
                    let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { break }
                    let data = Data(buffer.prefix(count))
                    DispatchQueue.main.async {
                        guard let self, self.helper === process else { return }
                        if !receiving { self.rateMeter?.add(data.count) }
                        self.terminal?.process.send(data: Array(data)[...])
                    }
                }
                process.waitUntilExit()
                errors.fileHandleForReading.readabilityHandler = nil
                try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
                DispatchQueue.main.async {
                    guard let self, self.helper === process else { return }
                    self.finishRate(completed: process.terminationStatus == 0)
                    self.stdin = nil; self.helper = nil; self.active = false; self.pending = Data(); self.detector = ZmodemDetector()
                    self.status = process.terminationStatus == 0 ? "Zmodem 传输完成" : "Zmodem 传输未完成（\(process.terminationStatus)）"
                    self.writer.async { try? input.fileHandleForWriting.close() }
                }
            }
        } catch { cancel(); status = "Zmodem 启动失败：\(error.localizedDescription)" }
    }
    private func write(_ data: Data, to handle: FileHandle) {
        guard queuedBytes + data.count <= 4 * 1024 * 1024 else { cancel(); status = "Zmodem 接收缓冲超限，已取消。"; return }
        queuedBytes += data.count
        writer.async { [weak self] in
            do { try handle.write(contentsOf: data) }
            catch {
                // The remote shell may print its prompt just after the sender closes
                // its pipe. Let helper termination establish success before treating
                // a closed pipe as a failed transfer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard let self, self.stdin === handle, self.helper?.isRunning == true else { return }
                    self.cancel()
                }
            }
            DispatchQueue.main.async { self?.queuedBytes -= data.count }
        }
    }
    func cancel() {
        guard active || awaitingReceiver else { return }
        finishRate(completed: false)
        receiverTimeout?.cancel(); receiverTimeout = nil; droppedURLs = nil; awaitingReceiver = false
        panel?.cancel(nil); panel = nil
        terminal?.process.send(data: Array(repeating: UInt8(24), count: 8)[...])
        if helper?.isRunning == true { helper?.terminate() }
        let input = stdin; writer.async { try? input?.close() }
        stdin = nil; helper = nil; pending = Data(); active = false; detector = ZmodemDetector(); status = "Zmodem 已取消"
    }
}

struct ZmodemStatusView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var bridge: ZmodemBridge
    var body: some View {
        if !bridge.status.isEmpty {
            HStack {
                Text(L10n.text(bridge.status)).font(.caption).foregroundStyle(.secondary)
                if bridge.active || bridge.rateIsAverage {
                    Text("\(L10n.text(bridge.rateIsAverage ? "平均" : bridge.receiving ? "下载" : "上传")) \(ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, bridge.bytesPerSecond))), countStyle: .file))/s")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .help("最近约 2 秒的 ZMODEM 数据流速率，包含协议开销和重传；完成后显示平均速率。")
                }
                Spacer()
                if bridge.active || bridge.awaitingReceiver { Button("取消 Zmodem", action: bridge.cancel).controlSize(.small) }
            }.padding(.horizontal, 12).padding(.vertical, 5)
        }
    }
}

import SwiftUI
