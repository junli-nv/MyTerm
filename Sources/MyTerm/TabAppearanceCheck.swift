import AppKit
import MyTermCore

enum TabAppearanceCheck {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Tab appearance: " + message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-tab-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(applicationSupportDirectory: root)
        defer { workspace.stopAll() }
        let server = Server(name: "fixture", host: "example.invalid")
        try require(workspace.save(server), "Save fixture failed")
        let first = TerminalSession(label: "fixture", executable: "/usr/bin/ssh", arguments: [], server: server)
        let second = TerminalSession(label: "fixture copy", executable: "/usr/bin/ssh", arguments: [], server: server)
        workspace.sessions = [first, second]
        let metadata = TabAppearance(color: .red, environment: "PROD")
        workspace.updateTab(first, name: "renamed", appearance: metadata)
        try require(first.label == "renamed" && second.label == "fixture copy", "Combined editor renamed another tab")
        workspace.updateTab(first, name: "invalid", appearance: TabAppearance(color: .blue, environment: String(repeating: "x", count: 25)))
        try require(first.label == "renamed" && first.appearance == metadata, "Invalid metadata partially renamed the tab")
        workspace.error = nil
        try require(first.appearance == metadata && second.appearance == metadata, "Open tabs did not update together")
        try require(first.sourceServer?.tabAppearance == metadata, "Reconnect/duplicate snapshot stale")
        let repository = workspace.repository
        try require(try repository.load().first?.tabAppearance == metadata, "Saved server lost metadata")
        let snapshot = workspace.sessionSnapshot(named: "fixture")
        try require(snapshot.tabs.allSatisfy { $0.tabAppearance == metadata }, "Session snapshot lost metadata")
        let native = SessionTabNativeView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        native.configure(title: "fixture", symbol: "network", selected: true, sessionID: first.id, appearance: metadata)
        native.layoutSubtreeIfNeeded()
        let fields = native.subviews.compactMap { $0 as? NSTextField }
        try require(fields.contains { $0.stringValue == "PROD" && !($0.isHidden) }, "Environment badge missing")
        try require(native.toolTip?.contains("PROD") == true, "Environment not available in tooltip")
        workspace.setTabAppearance(TabAppearance(), for: first)
        try require(second.appearance == TabAppearance(), "Reset did not propagate")
        print("PASS: tab environment/color persistence, existing SSH tabs, reconnect snapshots, saved workspaces and native badge")
    }
}
