import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MyTermCore

final class TerminalDiagnostics: ObservableObject {
    static let shared = TerminalDiagnostics()
    let log = TerminalDiagnosticLog()
    @Published var message = ""
    @Published var exporting = false
    private var window: NSWindow?
    func present(workspace: Workspace) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 330),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.contentMinSize = NSSize(width: 580, height: 330)
            panel.contentView = NSHostingView(rootView: TerminalDiagnosticsView(model: self, workspace: workspace))
            panel.center(); window = panel
        }
        refreshTitle()
        window?.makeKeyAndOrderFront(nil)
    }
    func refreshTitle() { window?.title = L10n.text("终端诊断") }
    private struct TerminalInfo: Codable {
        let id: UUID, kind: String
        let state: TerminalDiagnosticLog.State
    }
    private struct Report: Encodable {
        let schema = 2
        let version: String, build: String, macOS: String
        let captured: Date
        let peakResidentBytes: Int64
        let terminals: [TerminalInfo]
        let trace: TerminalDiagnosticLog.Snapshot
        let mcp: CodexMCPDiagnosticLog.Snapshot
        let mcpSecurity: CodexMCPSecurityCheck.Report?
    }
    func report(workspace: Workspace) throws -> Data {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let terminals = workspace.sessions.map { session in
            TerminalInfo(id: session.terminal.diagnosticTrace.id,
                         kind: session.isCodexSession ? "codex" : session.server == nil ? "local" : "ssh",
                         state: TerminalDiagnosticTrace.state(session.terminal))
        }
        let report = Report(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString, captured: Date(),
            peakResidentBytes: Int64(usage.ru_maxrss), terminals: terminals, trace: log.snapshot(), mcp: CodexMCPDiagnosticLog.shared.snapshot(), mcpSecurity: workspace.codex.mcpSecurity)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    /// Export only explicitly constructed metadata, never collect user files or configurations.
    static func archive(_ data: Data, to destination: URL) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-diagnostic-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("MyTerm-Diagnostics")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try data.write(to: contents.appendingPathComponent("diagnostic.json"), options: .atomic)
        let instructions = "诊断包不包含输入文字、输出正文、密码、主机名或配置文件。请附上问题发生时间、复现步骤和预期行为。\nThis archive contains metadata only, not input/output text, passwords, hostnames or configuration files. Include the incident time, reproduction steps and expected behavior.\n"
        try instructions.write(to: contents.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let zip = root.appendingPathComponent("report.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", contents.path, zip.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ConfigurationError.invalid("诊断包导出失败。") }
        try Data(contentsOf: zip).write(to: destination, options: .atomic)
    }
    func export(workspace: Workspace) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "MyTerm-Diagnostics.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let data = try report(workspace: workspace)
            exporting = true
            DispatchQueue.global(qos: .utility).async {
                let success: Bool
                do { try Self.archive(data, to: destination); success = true } catch { success = false }
                DispatchQueue.main.async {
                    self.exporting = false
                    self.message = success ? "诊断包已导出。请附上问题发生时间和复现步骤。" : "诊断包导出失败。"
                }
            }
        } catch { message = "诊断包导出失败。" }
    }
}

private struct TerminalDiagnosticsView: View {
    @ObservedObject var model: TerminalDiagnostics
    @ObservedObject var workspace: Workspace
    @ObservedObject var language = LanguagePreferences.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = model.log.snapshot()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("终端诊断")).font(.title2.bold())
                    Text(L10n.text("默认关闭。终端事件仅在内存记录，MCP 元数据写入本机私有文件。每次最多 15 分钟，保留最新 5000 条终端事件和 256 条 MCP 事件。不采集输入文字、输出正文、密码、令牌、主机名或配置文件；不自动上传。"))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(snapshot.recording ? "正在记录诊断" : "诊断记录已停止") + " · \(snapshot.entries.count) / 5000")
                    HStack {
                        Button(L10n.text(snapshot.recording ? "停止记录" : "开始新记录")) {
                            if snapshot.recording { model.log.stop(); CodexMCPDiagnosticLog.shared.stop() } else { model.log.start(); CodexMCPDiagnosticLog.shared.start() }
                            model.message = ""
                        }
                        Button(L10n.text("标记刚刚发生问题")) { model.log.record(.marker); model.message = "已标记问题时间。" }.disabled(!snapshot.recording)
                        Button(L10n.text("清除记录")) { model.log.clear(); CodexMCPDiagnosticLog.shared.clear(); model.message = "" }
                    }
                    Button(L10n.text("导出诊断包…")) { model.export(workspace: workspace) }.disabled(model.exporting)
                    Text(L10n.text("复现前开始记录，再启动 Codex 标签；出现问题后停止并导出。关闭此窗口不会停止记录；退出应用清空终端事件，MCP 记录保留至清除或开始新记录。"))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !model.message.isEmpty { Text(L10n.text(model.message)).fixedSize(horizontal: false, vertical: true) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.visible)
        }.environment(\.locale, language.locale)
            .onReceive(NotificationCenter.default.publisher(for: LanguagePreferences.didChange)) { _ in model.refreshTitle() }
    }
}
