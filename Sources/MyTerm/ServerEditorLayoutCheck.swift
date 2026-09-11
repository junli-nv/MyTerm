import AppKit
import MyTermCore

enum ServerEditorLayoutCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-editor-check-\(UUID())")
        let workspace = Workspace(applicationSupportDirectory: directory)
        let controller = ServerEditorWindowController()
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { controller.close(); language.selection = original; try? FileManager.default.removeItem(at: directory) }
        var server = Server(name: "Layout test", host: "example.com")
        server.proxy = NetworkProxy()
        server.jumpServers = [SSHJumpServer(host: "jump-one"), SSHJumpServer(host: "jump-two")]
        server.forwards = [PortForward(listenPort: "12345", destinationPort: "23456"),
                           PortForward(kind: .remote, listenPort: "12346", destinationPort: "23457"),
                           PortForward(kind: .dynamic, listenPort: "12347")]
        controller.present(server: server, workspace: workspace)
        let window = controller.window!, root = window.contentView!
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("SSH editor layout: " + message) }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)); root.layoutSubtreeIfNeeded() }
        try require(window.styleMask.contains(.resizable) && window.collectionBehavior.contains(.fullScreenPrimary), "Window cannot resize/fullscreen")
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            for size in [NSSize(width: 640, height: 480), NSSize(width: 900, height: 760)] {
                window.setContentSize(size); settle()
                guard let scroll = descendants(root).compactMap({ $0 as? NSScrollView }).first(where: { $0.identifier?.rawValue == "ssh.editor.scroll" }),
                      let document = scroll.documentView else { throw ConfigurationError.invalid("SSH editor scrolling missing") }
                try require(scroll.hasVerticalScroller && !scroll.autohidesScrollers && scroll.scrollerStyle == .legacy, "Scrollbar is hidden")
                try require(document.frame.width <= scroll.contentSize.width + 1, "Horizontal overflow")
                let maximum = document.frame.height - scroll.contentSize.height
                try require(maximum > 100, "Expanded controls are compressed instead of scrollable")
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum)); scroll.reflectScrolledClipView(scroll.contentView); settle()
                try require(scroll.contentView.bounds.origin.y > 100, "Cannot reach forwarding controls")
                let ports = descendants(document).compactMap { $0 as? NSTextField }.filter { ["12345", "23456", "12346", "23457", "12347"].contains($0.stringValue) }
                try require(ports.count == 5, "Forwarding fields missing")
                for field in ports { try require(field.bounds.width >= 140 && field.bounds.height >= 18, "Port field clipped") }
            }
        }
        window.setContentSize(NSSize(width: 640, height: 480)); settle()
        let before = window.frame
        window.performZoom(nil); settle()
        try require(window.frame.width > before.width || window.frame.height > before.height, "Maximize did not enlarge window")
        window.performZoom(nil); settle()
        try require(abs(window.frame.width - before.width) < 2 && abs(window.frame.height - before.height) < 2, "Restore changed window size")
        print("PASS: SSH editor: expanded jumps/proxy/three forwarding types, Chinese/English, small/large windows, persistent scrollbar, unclipped ports and maximize/restore")
    }
}
