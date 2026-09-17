import SwiftUI
import MyTermCore

private final class ServerTreeState: ObservableObject {
    @Published var ungroupedExpanded = true
}

/// One-level folder tree. Saved groups retain their existing IDs and collapse state.
struct ServerGroupsView: View {
    @StateObject private var tree = ServerTreeState()
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var workspace: Workspace
    private var ungrouped: [Server] {
        let assigned = Set(workspace.groups.flatMap(\.serverIDs))
        return workspace.servers.filter { !assigned.contains($0.id) }
    }
    private func matches(_ server: Server) -> Bool {
        workspace.search.isEmpty || "\(server.displayName) \(server.host) \(server.user)".localizedCaseInsensitiveContains(workspace.search)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(workspace.groups) { group in
                let members = workspace.servers.filter { group.serverIDs.contains($0.id) }
                let groupMatches = !workspace.search.isEmpty && group.name.localizedCaseInsensitiveContains(workspace.search)
                let visible = members.filter { groupMatches || matches($0) }
                if workspace.search.isEmpty || groupMatches || !visible.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Button { workspace.toggleGroup(group) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: group.collapsed && workspace.search.isEmpty ? "chevron.right" : "chevron.down").font(.caption2)
                                Image(systemName: group.collapsed && workspace.search.isEmpty ? "folder" : "folder.fill")
                                Text(group.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(members.count)").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu {
                            Button("重命名…") { workspace.editGroup(group) }
                            Button("删除分组（保留服务器）", role: .destructive) { workspace.deleteGroup(group) }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                    }.font(.caption).padding(.vertical, 5)
                    .contextMenu {
                        Button("重命名…") { workspace.editGroup(group) }
                        Button("删除分组（保留服务器）", role: .destructive) { workspace.deleteGroup(group) }
                    }
                    if !group.collapsed || !workspace.search.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { server in ServerGroupRow(server: server, workspace: workspace) }
                        if members.isEmpty { Text("拖拽会话到此加入分组").font(.caption2).foregroundStyle(.secondary).padding(.leading, 16) }
                        }.modifier(ServerTreeChildren())
                    }
                    }
                    .modifier(ServerGroupDropTarget(workspace: workspace, groupID: group.id))
                }
            }
            let visible = ungrouped.filter(matches)
            if !workspace.groups.isEmpty || !visible.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                Button { tree.ungroupedExpanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tree.ungroupedExpanded || !workspace.search.isEmpty ? "chevron.down" : "chevron.right").font(.caption2)
                        Image(systemName: "folder")
                        Text("未分组")
                        Spacer(minLength: 0)
                        Text("\(ungrouped.count)").foregroundStyle(.secondary)
                    }.font(.caption).padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .modifier(ServerGroupDropTarget(workspace: workspace, groupID: nil))
                if tree.ungroupedExpanded || !workspace.search.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { server in
                            ServerGroupRow(server: server, workspace: workspace)
                                .modifier(ServerGroupDropTarget(workspace: workspace, groupID: nil, targetServerID: server.id))
                                .help("拖入另一个未分组会话以创建分组；双击连接")
                        }
                        Text("拖拽会话到此退出分组").font(.caption2).foregroundStyle(.secondary)
                            .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(ServerGroupDropTarget(workspace: workspace, groupID: nil))
                    }.modifier(ServerTreeChildren())
                }
                }
            }
            if workspace.servers.isEmpty && workspace.groups.isEmpty {
                Text("添加常用服务器，\n双击即可打开 SSH 会话。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Indentation and a continuous guide make parent/child relationships visible.
private struct ServerTreeChildren: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.leading, 20)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1)
                    .padding(.leading, 6).allowsHitTesting(false)
            }
    }
}

private struct ServerGroupRow: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    let server: Server
    @ObservedObject var workspace: Workspace
    var body: some View {
        HStack(spacing: 10) {
                Image(systemName: "server.rack").foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName).fontWeight(.medium).lineLimit(1)
                    Text(server.user.isEmpty ? server.host : "\(server.user)@\(server.host)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 5).padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading)

        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.connect(server) }
        .onDrag { SavedServerDrag(id: server.id).itemProvider }
        .help("双击连接 SSH 会话")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { workspace.connect(server) }
        .contextMenu {
            Button("连接") { workspace.connect(server) }
            Button("编辑…") { workspace.editor = server }
            Menu("移至分组") {
                Button("未分组") { workspace.moveServer(server, to: nil) }
                ForEach(workspace.groups) { group in
                    Button(group.name) { workspace.moveServer(server, to: group.id) }
                }
            }
            Divider()
            Button("删除配置", role: .destructive) { workspace.delete(server) }
        }
    }
}
