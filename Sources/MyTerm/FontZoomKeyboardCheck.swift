import AppKit
import MyTermCore

/// Exercise AppKit shortcut routing, including inactive terminal and editor focus.
enum FontZoomKeyboardCheck {
    static func run() throws {
        let preferences = ThemePreferences.shared
        let original = preferences.theme.fontSize
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { preferences.theme.fontSize = original; window.close() }
        let terminal = MouseTerminalView(frame: window.contentLayoutRect)
        window.contentView = terminal
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Font zoom keyboard: " + message) }
        }
        func key(_ text: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: text == "-" ? 27 : 24)!
        }
        preferences.theme.fontSize = 14
        try require(window.performKeyEquivalent(with: key("=", modifiers: .command)), "Command = not consumed")
        try require(preferences.theme.fontSize == 14.5, "Command = did not enlarge")
        try require(window.performKeyEquivalent(with: key("+", modifiers: [.command, .shift])), "Command + not consumed")
        try require(preferences.theme.fontSize == 15, "Command + did not enlarge")
        try require(window.performKeyEquivalent(with: key("-", modifiers: .command)), "Command - not consumed")
        try require(preferences.theme.fontSize == 14.5, "Command - did not shrink")
        _ = terminal.performKeyEquivalent(with: key("=", modifiers: [.command, .option]))
        _ = terminal.performKeyEquivalent(with: key("+", modifiers: .control))
        try require(preferences.theme.fontSize == 14.5, "Unrelated modifiers changed font size")
        preferences.theme.fontSize = 5
        _ = window.performKeyEquivalent(with: key("-", modifiers: .command))
        try require(preferences.theme.fontSize == 5, "Lower limit ignored")
        preferences.theme.fontSize = 36
        _ = window.performKeyEquivalent(with: key("+", modifiers: .command))
        try require(preferences.theme.fontSize == 36, "Upper limit ignored")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        terminal.addSubview(field); window.makeFirstResponder(field)
        _ = terminal.performKeyEquivalent(with: key("-", modifiers: .command))
        try require(preferences.theme.fontSize == 36, "Editor focus changed terminal font")
        print("PASS: Command +/-/= font zoom, half-point steps, bounds and editor focus isolation")
    }
}
