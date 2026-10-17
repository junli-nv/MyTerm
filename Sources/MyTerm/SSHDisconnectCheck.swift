import AppKit
import SwiftUI
import SwiftTerm
import MyTermCore

enum SSHDisconnectCheck {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("SSH disconnect: " + message) }
        }
        let session = TerminalSession(label: "Disconnect check", executable: "/usr/bin/ssh", arguments: [])
        let view = session.terminal
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = root
        view.frame = root.bounds; root.addSubview(view)
        defer { session.stop(); window.close() }
        view.resize(cols: 40, rows: 12)
        view.feed(text: (1...6).map { "PRESERVE_ROW_\($0)\r\n" }.joined())
        view.feed(text: "NORMAL_HISTORY\r\n\u{1b}[?1049h\u{1b}[HREMOTE_SCREEN 中文\r\nlast output\u{1b}[2;5r\u{1b}[?6h\u{1b}[8m\u{1b}[?25l\u{1b}[?1000h\u{1b}[?2026h\u{1b}]0;unfinished")
        session.handleProcessTermination(exitCode: 255 << 8)
        try require(session.canReconnect && !session.isRunning, "SSH failure did not enable reconnect")
        let text = session.historySnapshot().text
        for row in 1...6 { try require(text.contains("PRESERVE_ROW_\(row)"), "Disconnect presentation overwrote row \(row)") }
        try require(text.contains("NORMAL_HISTORY") && text.contains("REMOTE_SCREEN 中文") && text.contains("last output"), "Previous output lost")
        try require(text.contains("R/r"), "Visible reconnect hint missing")
        try require(!view.getTerminal().isCurrentBufferAlternate && !view.getTerminal().synchronizedOutputActive && view.getTerminal().mouseMode == .off, "Remote modes remained active")
        let button = NSButton(title: "Reconnect", target: nil, action: nil)
        root.addSubview(button)
        window.makeFirstResponder(button)
        var reconnects = 0
        view.reconnectHandler = { reconnects += 1 }
        func event(_ key: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: 15)!
        }
        try require(view.handleReconnectEvent(event("r")), "Lowercase reconnect lost with control focus")
        try require(view.handleReconnectEvent(event("R", flags: .shift)), "Uppercase reconnect lost")
        try require(!view.handleReconnectEvent(event("r", flags: .command)), "Command shortcut intercepted")
        view.isHidden = true
        try require(!view.handleReconnectEvent(event("r")), "Hidden session consumed key")
        view.isHidden = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        root.addSubview(editor); window.makeFirstResponder(editor)
        try require(!view.handleReconnectEvent(event("r")), "Editor typing consumed")
        try require(reconnects == 2, "Reconnect invoked more than once per key")
        let language = LanguagePreferences.shared
        let previousLanguage = language.selection
        defer { language.selection = previousLanguage }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            let bar = NSHostingView(rootView: TerminalStatusBar(session: session).environment(\.locale, language.locale))
            window.contentView = bar
            for width in [1400.0, 400.0, 1000.0] {
                window.setContentSize(NSSize(width: width, height: 40))
                RunLoop.main.run(until: Date().addingTimeInterval(0.15)); bar.layoutSubtreeIfNeeded()
                guard let scroll = descendants(bar).compactMap({ $0 as? NSScrollView }).first,
                      let document = scroll.documentView else { throw ConfigurationError.invalid("Missing SSH status scrollbar") }
                if width >= 760 {
                    try require(abs(document.frame.width - scroll.contentSize.width) < 2, "Disconnected status bar did not fill the pane")
                } else {
                    try require(document.frame.width > scroll.contentSize.width && bar.frame.width <= width + 1, "Narrow status bar did not scroll")
                }
            }
        }
        print("PASS: disconnected SSH status bar fills wide panes and scrolls in narrow panes in both languages")
        print("PASS: SSH disconnect: normal/full-screen output retained, visible hint, display modes reset, R/r with control focus, hidden/editor shortcut isolation")
    }
}
