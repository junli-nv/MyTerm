import AppKit
import SwiftUI
import MyTermCore

enum JumpManagerCheck {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jump-manager-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(applicationSupportDirectory: root)
        var hop = SSHJumpServer(host: "independent.test", user: "fixture", authentication: .key)
        try workspace.saveJumpProfile(hop)
        guard Workspace(applicationSupportDirectory: root).jumpProfiles.count == 1 else { throw ConfigurationError.invalid("Unused jump not retained") }
        var server = Server(name: "Reference", host: "target.test")
        hop = workspace.jumpProfiles[0]
        server.jumpServers = [hop]
        guard workspace.save(server) else { throw ConfigurationError.invalid("Cannot save jump reference") }
        do { try workspace.deleteJumpProfile(hop.id); throw ConfigurationError.invalid("Referenced jump was deleted") }
        catch { guard workspace.jumpProfiles.count == 1 else { throw error } }
        hop.editableName = "Dallas 跳板"; hop.port = "2222"; try workspace.saveJumpProfile(hop)
        guard workspace.servers[0].jumpServers![0].port == "2222" else { throw ConfigurationError.invalid("Jump edit not propagated") }
        guard workspace.servers[0].jumpServers![0].name == hop.name,
              Workspace(applicationSupportDirectory: root).jumpProfiles[0].name == hop.name,
              workspace.sharedJumpTitle(hop).contains("Dallas 跳板") else { throw ConfigurationError.invalid("Jump name not persisted or propagated") }
        let language = LanguagePreferences.shared, previous = language.selection
        let originalWindow = NSApp.keyWindow
        defer { language.selection = previous; originalWindow?.makeKeyAndOrderFront(nil) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            let draft = JumpManagerDraft(); draft.select(hop)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 450), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: SharedJumpManagerView(workspace: workspace, draft: draft)); hosting.sizingOptions = []
            window.contentView = hosting; window.orderFront(nil); window.setContentSize(NSSize(width: 700, height: 450))
            RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded()
            guard hosting.frame.height <= 451, descendants(hosting).compactMap({ $0 as? NSScrollView }).count >= 2 else {
                window.close(); throw ConfigurationError.invalid("Jump manager minimum layout failed")
            }
            window.close()
        }
        workspace.delete(workspace.servers[0])
        try workspace.deleteJumpProfile(hop.id)
        guard Workspace(applicationSupportDirectory: root).jumpProfiles.isEmpty else { throw ConfigurationError.invalid("Jump deletion not persisted") }
        print("PASS: jump manager standalone create/reload, reference deletion protection, propagated edit, deletion and bilingual minimum layout")
    }
}
