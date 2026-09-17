import SwiftUI
import MyTermCore

/// Uses temporary storage and the real naming dialog; no connections are started.
enum ServerTreeCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyTerm-tree-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = Workspace(applicationSupportDirectory: directory)
        let first = Server(host: "tree-a.example"), second = Server(host: "tree-b.example")
        workspace.servers = [first, second]
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid(message) }
        }
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        func prompt(cancel: Bool) -> Bool {
            let timer = Timer(timeInterval: 0.1, repeats: false) { _ in
                if let root = NSApp.modalWindow?.contentView,
                   let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) {
                    NSApp.modalWindow?.makeFirstResponder(nil)
                    field.stringValue = "拖拽新分组"
                }
                NSApp.stopModal(withCode: cancel ? .alertSecondButtonReturn : .alertFirstButtonReturn)
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            defer { timer.invalidate() }
            return workspace.promptGroupFromServers(first.id, target: second.id)
        }
        try require(!prompt(cancel: true) && workspace.groups.isEmpty, "Cancelling folder creation changed groups")
        try require(prompt(cancel: false), "Naming a folder failed")
        let saved = try SessionGroupRepository(url: directory.appendingPathComponent("MyTerm/groups.json")).load()
        try require(saved == workspace.groups && saved.count == 1 && Set(saved[0].serverIDs) == Set([first.id, second.id]), "Folder members were not saved atomically")
        try require(!workspace.canGroupServers(first.id, with: second.id) && !workspace.canGroupServers(first.id, with: first.id), "Grouped/self drop was accepted")
        workspace.toggleGroup(saved[0])
        try require(workspace.groups[0].collapsed, "Folder collapse failed")
        try require(workspace.moveDraggedServers([first.id, second.id], to: nil), "Ungroup drop failed")
        do {
            try workspace.createGroupFromServers(first.id, target: second.id, name: saved[0].name)
            throw ConfigurationError.invalid("Duplicate folder name accepted")
        } catch {
            try require(workspace.groups.count == 1 && workspace.groups[0].serverIDs.isEmpty, "Invalid name changed membership")
        }
        try require(!workspace.canGroupServers(first.id, with: UUID()), "Deleted target accepted")
        try require(workspace.sessions.isEmpty, "Grouping opened a connection")
        let language = LanguagePreferences.shared, previous = LanguagePreferences.shared.selection
        defer { language.selection = previous }
        for selection in [InterfaceLanguage.chinese, .english] {
            language.selection = selection
            let view = NSHostingView(rootView: ServerGroupsView(workspace: workspace))
            view.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
            view.layoutSubtreeIfNeeded()
            try require(view.fittingSize.width <= 241, "Folder tree overflowed sidebar")
        }
        print("PASS: server tree: naming/cancel, atomic persistence, self/stale/grouped drops, duplicate name, collapse, ungroup and bilingual sidebar layout")
    }
}
