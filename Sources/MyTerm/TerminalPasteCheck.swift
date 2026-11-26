import AppKit
import SwiftTerm
import MyTermCore

enum TerminalPasteCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }

    static func run() throws {
        let clipboard = NSPasteboard.general
        let saved = clipboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            clipboard.clearContents()
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { clipboard.writeObjects(items) }
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Terminal paste: " + message) }
        }
        let suite = "MyTerm.PasteCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MousePreferences(defaults: defaults)
        let frame = NSRect(x: 80, y: 80, width: 600, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: frame.offsetBy(dx: 650, dy: 0), styleMask: [.titled], backing: .buffered, defer: false)
        for item in [window, other] { item.isReleasedWhenClosed = false }
        defer { window.close(); other.close() }
        let input = RecordingTerminal(frame: NSRect(origin: .zero, size: frame.size))
        input.preferences = preferences
        window.contentView = input
        func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 50, y: 50), modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        }
        for alternate in [false, true] {
            if alternate { input.feed(text: "\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?1006h") }
            for bracketed in [false, true] {
                input.feed(text: bracketed ? "\u{1b}[?2004h" : "\u{1b}[?2004l")
                for payload in ["copied from editor", "中文\n  second line"] {
                    clipboard.clearContents(); clipboard.setString(payload, forType: .string)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(nil)
                    other.makeKeyAndOrderFront(nil)
                    try require(!window.isKeyWindow, "Fixture must start with an inactive terminal window")
                    try require(input.acceptsFirstMouse(for: event(.rightMouseDown)), "First paste click would be consumed by activation")
                    input.bytes = []
                    window.sendEvent(event(.rightMouseDown))
                    window.sendEvent(event(.rightMouseUp))
                    let expected = bracketed ? "\u{1b}[200~" + payload + "\u{1b}[201~" : payload
                    try require(String(decoding: input.bytes, as: UTF8.self) == expected,
                                "Single inactive-window click lost, duplicated or changed paste framing")
                    try require(window.firstResponder === input, "Paste did not restore terminal input focus")
                    try require(window.isKeyWindow, "Paste left the terminal window inactive; later typing goes to the previous window")
                }
            }
        }
        try require(!input.acceptsFirstMouse(for: event(.leftMouseDown)), "Ordinary left-click activation changed")
        try require(!input.acceptsFirstMouse(for: event(.rightMouseDown, flags: .shift)), "Menu gesture must retain native activation")
        preferences.rightClickPastes = false
        try require(!input.acceptsFirstMouse(for: event(.rightMouseDown)), "Disabled paste opted into first-click input")
        print("PASS: inactive-window first right-click pastes exactly once; UTF-8/multiline, normal/tmux mouse modes, bracketed framing, focus and activation policy")
    }
}
