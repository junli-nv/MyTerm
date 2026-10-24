import SwiftUI
import MyTermCore

struct SplitPaneView: View {
    @ObservedObject var workspace: Workspace
    let layout: PaneLayout
    var body: some View {
        VStack(spacing: 0) {
            if workspace.broadcastTabID != nil { PaneBroadcastPanel(workspace: workspace) }
            node(layout, divided: layout.leaves.count > 1)
        }
    }

    private func node(_ layout: PaneLayout, divided: Bool) -> AnyView {
        switch layout {
        case .leaf(let id):
            guard let session = workspace.sessions.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(VStack(spacing: 0) {
                if divided {
                    HStack(spacing: 8) {
                        Button { workspace.focusPane(id); workspace.focusSelectedPane() } label: {
                            HStack {
                                Circle().fill(workspace.selectedID == id ? Color.accentColor : .secondary).frame(width: 7, height: 7)
                                if workspace.broadcastTargets[id] != nil {
                                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.orange).help("广播目标")
                                }
                                Text(session.label).lineLimit(1)
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu {
                            Button("上下分屏") { workspace.focusPane(id); workspace.requestSplit(.horizontal) }
                            Button("左右分屏") { workspace.focusPane(id); workspace.requestSplit(.vertical) }
                            Button("上下分屏并选择会话…") { workspace.focusPane(id); workspace.requestSplit(.horizontal, chooseSession: true) }
                            Button("左右分屏并选择会话…") { workspace.focusPane(id); workspace.requestSplit(.vertical, chooseSession: true) }
                            Button("广播命令") { workspace.beginBroadcast() }
                            Button("移为独立标签") { workspace.detachPane(id) }
                        } label: { Image(systemName: "rectangle.split.2x2") }.menuStyle(.borderlessButton).fixedSize()
                        Button { workspace.close(session) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help("关闭当前分屏")
                    }.font(.caption).padding(.horizontal, 8).frame(height: 26)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
                TerminalPane(session: session, isFocused: workspace.selectedID == id, isSplit: divided)
            }.frame(minWidth: 240, minHeight: 140).id(id))
        case .split(let id, let axis, let first, let second):
            return AnyView(StablePaneSplit(axis: axis,
                first: node(first, divided: true), second: node(second, divided: true),
                fraction: workspace.paneFractions[id] ?? 0.5,
                saveFraction: { workspace.paneFractions[id] = $0 }).id(id))
        }
    }
}

final class SplitChooserState: ObservableObject { @Published var selection = "local" }

struct SplitSessionChooser: View {
    @ObservedObject var workspace: Workspace
    let request: SplitRequest
    @StateObject private var state = SplitChooserState()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(request.axis.title)).font(.title2.bold())
            Text("选择新分屏中的会话。移入已有会话不会重新连接。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    choice("新建本地终端", value: "local")
                    if let source = workspace.sessions.first(where: { $0.id == request.target }), source.sourceServer != nil {
                        choice("复制当前 SSH 连接", value: "duplicate")
                    }
                    if !workspace.servers.isEmpty {
                        Text("连接已保存的服务器").font(.headline).padding(.top, 8)
                        ForEach(workspace.servers) { server in choice(server.displayName, value: "server:" + server.id.uuidString, localized: false) }
                    }
                    Text("移入已有会话").font(.headline).padding(.top, 8)
                    ForEach(workspace.sessions.filter { $0.id != request.target }) { session in
                        choice(session.label, value: "session:" + session.id.uuidString, localized: false)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 180, maxHeight: 320)
            HStack {
                Button("取消") { workspace.splitRequest = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建分屏", action: create).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 460)
    }
    private func choice(_ title: String, value: String, localized: Bool = true) -> some View {
        Button { state.selection = value } label: {
            HStack {
                Image(systemName: state.selection == value ? "largecircle.fill.circle" : "circle")
                Text(localized ? L10n.text(title) : title).lineLimit(2)
                Spacer()
            }.contentShape(Rectangle()).padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
    private func create() {
        guard let target = workspace.sessions.first(where: { $0.id == request.target }) else { workspace.splitRequest = nil; return }
        let oldIDs = Set(workspace.sessions.map(\.id))
        var newID: UUID?
        if state.selection == "local" { workspace.newLocal(directory: target.directory) }
        else if state.selection == "duplicate" { workspace.duplicate(target) }
        else if state.selection.hasPrefix("server:"), let server = workspace.servers.first(where: { "server:" + $0.id.uuidString == state.selection }) { workspace.connect(server) }
        else if let existing = workspace.sessions.first(where: { "session:" + $0.id.uuidString == state.selection }) { newID = existing.id }
        if newID == nil { newID = workspace.sessions.first(where: { !oldIDs.contains($0.id) })?.id }
        if let newID { workspace.moveToSplit(newID, beside: target.id, axis: request.axis) }
        workspace.splitRequest = nil
    }
}
