import AppKit
import MyTermCore

/// Exercise the menu and modal editor, then inspect the rendered native title.
/// Reading only the model would miss a stale NSViewRepresentable.
enum SessionTabRenameCheck {
    static func run(window: NSWindow, workspace: Workspace) throws {
        guard let session = workspace.sessions.first else { return }
        let originalAppearance = session.appearance
        let originalName = session.label
        let originalSelection = workspace.selectedID
        defer { session.setAppearance(originalAppearance); session.label = originalName; workspace.selectedID = originalSelection }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Tab rename: " + message) }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func tab() throws -> SessionTabNativeView {
            guard let root = window.contentView,
                  let view = descendants(root).compactMap({ $0 as? SessionTabNativeView }).first(where: {
                      $0.identifier?.rawValue == "session.tab.menu." + session.id.uuidString
                  }) else { throw ConfigurationError.invalid("Rename tab missing") }
            return view
        }
        func displayedName() throws -> String? {
            descendants(try tab()).compactMap { $0 as? NSTextField }.first?.stringValue
        }
        func rename(_ name: String, cancel: Bool = false, environment: String? = nil) throws {
            let menu = try tab().buildMenu!()!
            guard let index = menu.items.firstIndex(where: { $0.title == L10n.text("编辑标签…") }) else {
                throw ConfigurationError.invalid("Rename menu item missing")
            }
            var edited = false
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
                if let root = NSApp.modalWindow?.contentView,
                   let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "tab.editor.name" }) {
                    NSApp.modalWindow?.makeFirstResponder(nil)
                    field.stringValue = name
                    if let environment {
                        descendants(root).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "tab.editor.environment" }?.stringValue = environment
                        descendants(root).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "tab.editor.color" }?.selectItem(at: 1)
                    }
                    edited = true
                }
                NSApp.stopModal(withCode: cancel ? .alertSecondButtonReturn : .alertFirstButtonReturn)
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            menu.performActionForItem(at: index)
            timer.invalidate()
            try require(edited, "Modal name field was not edited")
            settle()
        }
        workspace.selectedID = session.id
        settle()
        try rename("A")
        try require(session.label == "A" && displayedName() == "A", "Selected tab title did not refresh")
        let shortWidth = try tab().frame.width
        let longName = "重命名 SSH — terminal test"
        try rename(longName)
        try require(session.label == longName && displayedName() == longName, "Repeated rename left a stale title")
        try require(try tab().frame.width > shortWidth, "Tab width did not grow with its title")
        try rename(longName, environment: "TEST")
        try require(session.appearance.environment == "TEST" && session.appearance.color == .red, "Combined editor did not apply metadata")
        try rename("Cancelled", cancel: true, environment: "CANCELLED")
        try require(session.appearance.environment == "TEST", "Cancel changed metadata")
        try require(session.label == longName && displayedName() == longName, "Cancel changed the title")
        if let other = workspace.sessions.first(where: { $0.id != session.id }) {
            workspace.selectedID = other.id
            settle()
            try require(try displayedName() == longName, "Switching tabs lost the title")
            _ = workspace.moveSessionTab(session.id, to: other.id)
            settle()
            try require(try displayedName() == longName, "Reordering lost the title")
            _ = workspace.moveSessionTab(session.id, to: other.id)
        }
        print("PASS: tab rename: real menu/editor, immediate and repeated title updates, native width, cancel, switching and reordering")
    }
}
