import AppKit
import SwiftUI
import MyTermCore

enum SSHKeySettingsCheck {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-key-references-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("SSH key references: " + message) }
        }
        let file = root.appendingPathComponent("fixture-key")
        try Data("synthetic key fixture".utf8).write(to: file)
        try Data("synthetic public fixture".utf8).write(to: URL(fileURLWithPath: file.path + ".pub"))
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        let library = SSHKeyLibrary(directory: root)
        guard let key = try library.list().first(where: { $0.name == "fixture-key" }) else {
            throw ConfigurationError.invalid("SSH key fixture missing")
        }
        var server = Server(host: "fixture.invalid", identityFile: file.path)
        server.jumpServers = [SSHJumpServer(host: "hop.invalid", identityFile: alias.path)]
        var references = SSHKeyAssociations.references(server: server, session: "Saved / Fixture")
        references.append(SSHKeyReference(path: root.appendingPathComponent("unused-key").path, session: "Unrelated"))
        let state = SSHKeySettingsState(library: library, references: { references })
        state.refresh()
        try require(state.associations[key.id]?.count == 2, "Direct/jump/symlink association failed")
        var confirmations = [Bool]()
        try state.delete(key) { extra, affected in
            confirmations.append(extra)
            if affected.count != 2 { return false }
            return !extra
        }
        try require(confirmations == [false, true], "Referenced key did not require two confirmations")
        try require(FileManager.default.fileExists(atPath: file.path), "Cancelling second confirmation deleted key")
        confirmations = []
        try state.delete(key) { extra, _ in confirmations.append(extra); return false }
        try require(confirmations == [false], "Cancelling first confirmation did not stop deletion")
        // References added after the first alert must still trigger an extra confirmation.
        references = []
        confirmations = []
        try state.delete(key) { extra, _ in
            confirmations.append(extra)
            references = [SSHKeyReference(path: file.path, session: "New reference")]
            return !extra
        }
        try require(confirmations == [false, true] && FileManager.default.fileExists(atPath: file.path), "Stale list bypassed confirmation")
        try state.delete(key) { extra, _ in
            if extra { references.append(SSHKeyReference(path: file.path, session: "Another reference")) }
            return true
        }
        try require(FileManager.default.fileExists(atPath: file.path), "New references during confirmation were ignored")
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { language.selection = original }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        references = (0..<30).map { SSHKeyReference(path: file.path, session: "\($0) " + String(repeating: "关联会话 Long session name ", count: 5)) }
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 736, height: 550), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let view = NSHostingView(rootView: SSHKeySettingsView(state: state).environment(\.locale, language.locale))
            window.contentView = view; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2)); view.layoutSubtreeIfNeeded()
            let scrolls = descendants(view).compactMap { $0 as? NSScrollView }
            try require(!scrolls.isEmpty, "Key list is not scrollable")
            for scroll in scrolls {
                if let document = scroll.documentView { try require(document.frame.width <= scroll.contentSize.width + 1, "Key list overflows horizontally") }
            }
        }
        try state.delete(key) { _, _ in true }
        try require(!FileManager.default.fileExists(atPath: file.path), "Confirmed deletion failed")
        try require(!FileManager.default.fileExists(atPath: file.path + ".pub"), "Public key copy was not removed")
        try Data("synthetic unused key".utf8).write(to: file)
        references = []; confirmations = []
        try state.delete(key) { extra, _ in confirmations.append(extra); return true }
        try require(confirmations == [false] && !FileManager.default.fileExists(atPath: file.path), "Unused key deletion required an extra confirmation")
        print("PASS: SSH key references: direct/jump/symlink matching, cancellation, extra confirmation, stale references, deletion and bilingual scrolling")
    }
}
