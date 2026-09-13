import AppKit
import SwiftUI
import MyTermCore

/// Uses synthetic credentials only; never reveals the user's password store.
enum CredentialSettingsCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-credential-ui-\(UUID())")
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { language.selection = original; try? FileManager.default.removeItem(at: directory) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Credential settings: " + message) }
        }
        let server = Server(host: "credential-fixture.invalid")
        let account = try SSHPasswordMemory.scopeIdentifier(for: server) + ":fixture"
        let store = SQLitePasswordStore(directory: directory)
        for index in 0..<8 { try store.save("synthetic secret", account: index == 0 ? account : "legacy-\(index)", label: "Fixture \(index) · user@credential-fixture.invalid's password:") }
        try store.rename(account, name: String(repeating: "长名称", count: 40))
        let state = CredentialSettingsState(store: store)
        state.entries = try store.list()
        state.associations = CredentialSettingsState.matching(state.entries, references: [
            CredentialSessionReference(server: server, label: "Saved session / Fixture"),
            CredentialSessionReference(server: server, label: "Open · Fixture"),
            CredentialSessionReference(server: Server(host: "unrelated.invalid"), label: "Unrelated")
        ])
        try require(state.associations[account]?.count == 2, "Incorrect session association")
        try require(state.associations["legacy-1"]?.isEmpty == true, "Legacy credential incorrectly matched")
        let entry = state.entries.first(where: { $0.id == account })!
        try require(state.revealed.isEmpty, "Password visible by default")
        state.toggleReveal(entry)
        try require(state.revealed[account] == "synthetic secret", "Reveal failed")
        state.toggleReveal(entry)
        try require(state.revealed.isEmpty, "Hide failed")
        try store.save("updated synthetic secret", account: account)
        state.toggleReveal(entry)
        try require(state.revealed[account] == "updated synthetic secret", "Reveal returned stale password")
        state.hideAll()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 736, height: 550), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let root = NSHostingView(rootView: CredentialSettingsView(state: state, automaticallyRefresh: false).environment(\.locale, language.locale))
            window.contentView = root; window.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25)); root.layoutSubtreeIfNeeded()
            let scrolls = descendants(root).compactMap { $0 as? NSScrollView }
            try require(!scrolls.isEmpty, "Password list is not scrollable")
            for scroll in scrolls {
                if let document = scroll.documentView {
                    try require(document.frame.width <= scroll.contentSize.width + 1, "Password list overflows horizontally")
                }
            }
            state.toggleReveal(entry)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            try require(state.revealed.isEmpty, "Losing focus did not hide password")
            state.toggleReveal(entry)
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            try require(state.revealed.isEmpty, "Switching applications did not hide password")
        }
        print("PASS: password names, session associations, reveal/hide, focus privacy, Chinese/English scrollable layout")
    }
}
