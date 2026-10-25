import AppKit
import SwiftUI

/// Local catalog management never deletes Codex transcripts or project files.
struct CodexClusterManagement: View {
    @ObservedObject var clusters: CodexClusterModel
    @ObservedObject var workspace: Workspace
    @ObservedObject var selection: CodexChooserState
    private var openThreads: Set<String> { Set(workspace.sessions.compactMap(\.codexThreadID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MyTerm 独立维护此列表；在 Codex 中删除对话不会自动移除这里的记录。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("移除对话记录") {
                    guard let id = selection.conversationID else { return }
                    confirm("移除对话记录？") {
                        if clusters.removeConversation(id, openThreads: openThreads) {
                            selection.conversationID = clusters.conversations(in: selection.clusterID).first?.id
                            selection.resume = selection.conversationID != nil
                        }
                    }
                }.disabled(selection.conversationID == nil)
                Button("删除集群") {
                    guard let id = selection.clusterID else { return }
                    confirm("删除集群及其对话记录？") {
                        if clusters.removeCluster(id, openThreads: openThreads) {
                            selection.clusterID = nil; selection.conversationID = nil; selection.resume = false
                        }
                    }
                }.disabled(selection.clusterID == nil)
            }
            Text("新集群存储目录").font(.caption.bold())
            Text(clusters.projectsDirectory.path).textSelection(.enabled)
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("选择目录…") { chooseDirectory() }
                Button("恢复默认目录") { clusters.setProjectsDirectory(nil) }
                    .disabled(clusters.catalog.projectsDirectory == nil)
            }
            Text("更改仅影响新集群；已有集群保留原目录，不移动文件或修改 Codex 历史。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let id = selection.clusterID, let directory = clusters.directory(for: id) {
                Text("当前集群目录").font(.caption.bold())
                Text(directory.path).textSelection(.enabled).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func confirm(_ title: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = L10n.text(title)
        alert.informativeText = L10n.text("仅移除 MyTerm 的分类、对话索引及关联，不删除 Codex 历史或目录中的文件。仍打开的对话需先关闭标签。")
        alert.addButton(withTitle: L10n.text("删除"))
        alert.addButton(withTitle: L10n.text("取消"))
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { action() } }
        } else if alert.runModal() == .alertFirstButtonReturn { action() }
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = clusters.projectsDirectory
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { clusters.setProjectsDirectory(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url { clusters.setProjectsDirectory(url) }
    }
}
