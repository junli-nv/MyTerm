import AppKit
import SwiftUI
import MyTermCore

enum SSHConfigurationAuditCheck {
    static func run() throws {
        let originalWindow = NSApp.keyWindow
        defer { originalWindow?.makeKeyAndOrderFront(nil) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-audit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(applicationSupportDirectory: root)
        var server = Server(name: "Still references removed host", host: "target.test", user: "test")
        server.jumpServers = [SSHJumpServer(host: "removed.test", user: "jump", authentication: .password)]
        guard workspace.save(server) else { throw ConfigurationError.invalid("Cannot save audit fixture") }
        let model = SSHConfigurationAuditModel()
        model.refresh(workspace: workspace)
        let deadline = Date().addingTimeInterval(5)
        while model.loading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard !model.loading, model.rows.count == 2, model.rows[1].host == "removed.test", model.exportServers.count == 1 else {
            throw ConfigurationError.invalid("Audit reference or export snapshot missing: loading=\(model.loading), rows=\(model.rows.count), export=\(model.exportServers.count)")
        }
        let language = LanguagePreferences.shared, previous = language.selection
        defer { language.selection = previous }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = NSHostingView(rootView: SSHConfigurationAuditView(model: model, refresh: {}, finish: {}))
            view.sizingOptions = []
            window.contentView = view; window.orderFront(nil)
            window.setContentSize(NSSize(width: 620, height: 420))
            model.rows = SSHConfigurationAudit.inspect((0..<30).map { .init(server: server, source: "Fixture \($0)", exported: true) }, passwordAccounts: []).rows // Long report must scroll without growing the window.
            RunLoop.main.run(until: Date().addingTimeInterval(0.1)); view.layoutSubtreeIfNeeded()
            guard let scroll = descendants(view).compactMap({ $0 as? NSScrollView }).first,
                  let document = scroll.documentView, document.frame.height > scroll.contentSize.height,
                  view.frame.height <= 421 else { window.close(); throw ConfigurationError.invalid("Audit report did not scroll at minimum size: root=\(view.frame), scrolls=\(descendants(view).compactMap { $0 as? NSScrollView }.map { "\($0.contentSize) / \(String(describing: $0.documentView?.frame))" })") }
            window.close()
            model.rows = SSHConfigurationAudit.inspect([.init(server: server, source: "Fixture", exported: true)], passwordAccounts: []).rows
        }
        print("PASS: SSH inventory metadata loading, referenced jumps, captured export scope and bilingual scrolling")
    }
}
