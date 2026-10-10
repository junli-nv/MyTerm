import AppKit
import SwiftUI

/// Local work deliberately uses Codex's own execution policy, not SSH grants.
struct CodexLocalWorkView: View {
    @ObservedObject var bridge: CodexBridge
    @StateObject private var selection = CodexLocalWorkSelection()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("复用 Codex 配置中的登录和代理，直接启动独立的本地 Codex。无需先打开或关联 Bash、SSH 标签。")
                .fixedSize(horizontal: false, vertical: true)
            Text("工作目录（请确认）").font(.headline)
            HStack {
                TextField("本地目录", text: $selection.directory).textFieldStyle(.roundedBorder)
                Button("选择目录") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { selection.directory = url.path }
                }
            }
            Text("默认使用用户主目录，也可选择项目目录。本地命令与文件修改使用 Codex 自身的工作区沙盒和审批流程；所选工作目录允许 Codex 写入。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("启动本地 Codex") {
                bridge.launch(localDirectory: (selection.directory as NSString).expandingTildeInPath)
            }.disabled(bridge.busy || bridge.configurationIssue != nil || selection.directory.isEmpty)
            if let issue = bridge.configurationIssue { Text(L10n.text(issue)).foregroundStyle(.orange) }
        }
    }
}

final class CodexLocalWorkSelection: ObservableObject {
    @Published var directory = FileManager.default.homeDirectoryForCurrentUser.path
}
