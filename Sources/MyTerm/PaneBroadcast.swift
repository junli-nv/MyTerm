import SwiftUI
import MyTermCore

extension TerminalSession {
    /// A running SSH process may still be waiting for authentication.
    var acceptsBroadcast: Bool {
        guard !isCodexSession, isRunning, terminal.process.running,
              terminal.reconnectHandler == nil,
              terminal.zmodem?.active != true, terminal.zmodem?.awaitingReceiver != true else { return false }
        if executable == "/usr/bin/ssh" {
            guard let path = connectionContext?.controlPath else { return false }
            return FileManager.default.fileExists(atPath: path)
        }
        return executable == "/bin/bash"
    }
}

extension Workspace {
    func beginBroadcast() {
        guard let selectedID, layout(containing: selectedID).leaves.count > 1 else { return }
        broadcastTargets = [:]
        broadcastTabID = tabID(containing: selectedID)
    }
    func endBroadcast() { broadcastTargets = [:]; broadcastTabID = nil }

    /// Validate every target before sending anything. Never queue input for a reconnect.
    @discardableResult
    func sendBroadcast(_ command: String, confirmedReady: Bool) throws -> [String] {
        guard confirmedReady else { throw ConfigurationError.invalid("请先确认所选终端都处于空白 Shell 提示符。") }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.utf8.count <= 4096,
              !command.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }) else {
            throw ConfigurationError.invalid("请输入不含换行或控制字符的单行命令，最多 4096 字节。")
        }
        guard let selectedID, let anchor = broadcastTabID, tabID(containing: selectedID) == anchor,
              !broadcastTargets.isEmpty else { throw ConfigurationError.invalid("请选择当前标签中的目标分屏。") }
        let leaves = Set(layout(containing: selectedID).leaves)
        let targets = sessions.filter { broadcastTargets[$0.id] != nil }
        guard targets.count == broadcastTargets.count,
              targets.allSatisfy({ leaves.contains($0.id) && $0.acceptsBroadcast && broadcastTargets[$0.id] == $0.inputGeneration }) else {
            throw ConfigurationError.invalid("目标已断开、重连、移出或不可用；未发送命令，请重新选择目标。")
        }
        // Main-thread dispatch is synchronous: no delayed tasks can send to a future process.
        for target in targets { target.terminal.send(txt: command + "\r") }
        return targets.map(\.label)
    }
}

private final class BroadcastInput: ObservableObject {
    @Published var command = ""
    @Published var confirmedReady = false
    @Published var result = ""
}

struct PaneBroadcastPanel: View {
    @ObservedObject var workspace: Workspace
    @StateObject private var input = BroadcastInput()
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("广播命令", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                Text("\(workspace.broadcastTargets.count)").monospacedDigit()
                Text("个目标")
                Spacer()
                Button("结束广播") { workspace.endBroadcast() }
            }
            Text("仅发送完整单行命令，不同步键盘操作。请确认目标均处于空白 Shell 提示符；Vim、less、密码提示或正在运行的程序也会接收这些输入。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if let selectedID = workspace.selectedID {
                        ForEach(workspace.layout(containing: selectedID).leaves, id: \.self) { id in
                            if let session = workspace.sessions.first(where: { $0.id == id }) {
                                BroadcastTargetRow(workspace: workspace, session: session)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 96)
            TextField("单行命令（最多 4096 字节）", text: $input.command)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Toggle("所选终端都处于空白 Shell 提示符", isOn: $input.confirmedReady)
            HStack {
                Text(L10n.text(input.result)).font(.caption).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("发送并执行") {
                    do {
                        let labels = try workspace.sendBroadcast(input.command, confirmedReady: input.confirmedReady)
                        input.result = L10n.text("已发送至：") + labels.joined(separator: ", ")
                        input.command = ""
                    } catch { input.result = L10n.text(error.localizedDescription) }
                    input.confirmedReady = false
                }.disabled(!input.confirmedReady || workspace.broadcastTargets.isEmpty || input.command.isEmpty)
            }
        }.padding(12)
        }.frame(maxHeight: 240).background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: workspace.broadcastTargets) { _ in input.confirmedReady = false; input.result = "" }
    }
}

private struct BroadcastTargetRow: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var session: TerminalSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
        HStack {
            Toggle(isOn: Binding(get: { workspace.broadcastTargets[session.id] != nil }, set: { selected in
                if selected { workspace.broadcastTargets[session.id] = session.inputGeneration }
                else { workspace.broadcastTargets.removeValue(forKey: session.id) }
            })) {
                Text(session.label).lineLimit(2)
                Text(session.sourceServer.map { "\($0.user)@\($0.host):\($0.port)" } ?? L10n.text("本地 Bash"))
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(!session.acceptsBroadcast && workspace.broadcastTargets[session.id] == nil)
            if !session.acceptsBroadcast { Text("不可用").font(.caption).foregroundStyle(.secondary) }
        }
        }
    }
}
