import SwiftUI
import MyTermCore

struct SplitRequest: Identifiable {
    let id = UUID()
    let target: UUID
    let axis: PaneAxis
}

extension Workspace {
    func sessionSnapshot(named name: String) -> SavedSession {
        let layouts = visibleTabs.map { layout(containing: $0.id) }
        let ids = layouts.flatMap(\.leaves)
        let ordered = ids.compactMap { id in sessions.first(where: { $0.id == id }) }
        var saved = SavedSession(name: name, tabs: ordered.map {
            SessionTab(server: $0.sourceServer, directory: $0.sourceServer == nil ? $0.directory : nil, encoding: $0.encoding, historyLogging: $0.historyLogging)
        }, selectedIndex: ids.firstIndex(where: { $0 == selectedID }) ?? 0)
        saved.paneSessionIDs = ids; saved.paneLayouts = layouts
        return saved
    }
    var visibleTabs: [TerminalSession] {
        let hidden = Set(paneLayouts.flatMap { key, layout in layout.leaves.filter { $0 != key } })
        return sessions.filter { !hidden.contains($0.id) }
    }
    func tabID(containing id: UUID) -> UUID {
        paneLayouts.first(where: { $0.value.leaves.contains(id) })?.key ?? id
    }
    func layout(containing id: UUID) -> PaneLayout { paneLayouts[tabID(containing: id)] ?? .leaf(id) }
    func selectTab(_ session: TerminalSession, focus: Bool = true) {
        let leaves = layout(containing: session.id).leaves
        let remembered = paneFocus[tabID(containing: session.id)]
        selectedID = remembered.flatMap { leaves.contains($0) ? $0 : nil } ?? session.id
        if focus { focusSelectedPane() }
    }
    func focusPane(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        if selectedID != id { selectedID = id }
        paneFocus[tabID(containing: id)] = id
    }
    func focusSelectedPane() {
        guard let terminal = selected?.terminal, let window = terminal.window else { return }
        window.makeFirstResponder(terminal)
    }
    func requestSplit(_ axis: PaneAxis, chooseSession: Bool = false) {
        guard let id = selectedID, selected != nil else { return }
        if let terminal = selected?.terminal, terminal.window != nil {
            let space = axis == .vertical ? terminal.bounds.width : terminal.bounds.height
            if space < (axis == .vertical ? 480 : 280) { error = "当前区域太小，请先放大窗口或调整分隔线。"; return }
        }
        guard let source = selected else { return }
        // Codex is not a shell connection that can be duplicated implicitly.
        if chooseSession || source.isCodexSession {
            splitRequest = SplitRequest(target: id, axis: axis)
            return
        }
        let existingIDs = Set(sessions.map(\.id))
        duplicate(source)
        guard let created = selected, !existingIDs.contains(created.id) else { return }
        moveToSplit(created.id, beside: id, axis: axis)
        focusSelectedPane()
    }
    /// Moving a live pane changes membership only; Codex associations retain UUIDs.
    @discardableResult
    func moveToSplit(_ id: UUID, beside target: UUID, axis: PaneAxis) -> Bool {
        guard id != target, sessions.contains(where: { $0.id == id }), sessions.contains(where: { $0.id == target }) else { return false }
        removePaneLayout(id)
        let anchor = tabID(containing: target)
        paneLayouts[anchor] = layout(containing: target).inserting(id, beside: target, axis: axis)
        focusPane(id)
        return true
    }
    func removePaneLayout(_ id: UUID) {
        if broadcastTabID != nil { endBroadcast() }
        defer {
            let liveNodes = Set(paneLayouts.values.flatMap(\.nodeIDs))
            paneFractions = paneFractions.filter { liveNodes.contains($0.key) }
        }
        let anchor = tabID(containing: id)
        guard let old = paneLayouts.removeValue(forKey: anchor) else { return }
        let remembered = paneFocus.removeValue(forKey: anchor)
        if let remaining = old.removing(id), let first = remaining.leaves.first {
            let newAnchor = anchor == id ? first : anchor
            if remaining.leaves.count > 1 { paneLayouts[newAnchor] = remaining }
            paneFocus[newAnchor] = remembered.flatMap { remaining.leaves.contains($0) ? $0 : nil } ?? first
        }
    }
    func detachPane(_ id: UUID) {
        removePaneLayout(id)
        focusPane(id)
    }
    func closeTab(containing id: UUID) {
        let ids = Set(layout(containing: id).leaves)
        for session in sessions.filter({ ids.contains($0.id) }) { close(session) }
    }
}
