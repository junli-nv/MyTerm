import AppKit
import Carbon.HIToolbox
import SwiftTerm
import MyTermCore

/// Synthetic repeat delivery and IME composition regression. Physical long-press
/// timing is supplied by macOS rather than simulated by the terminal.
enum KeyboardRepeatCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Keyboard repeat: " + message) }
        }
        try require(!UserDefaults.standard.bool(forKey: "ApplePressAndHoldEnabled"), "App accent menu still enabled")
        guard let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
            throw ConfigurationError.invalid("Keyboard repeat: ASCII input source unavailable")
        }
        defer { TISSelectInputSource(original) }
        try require(TISSelectInputSource(ascii) == noErr, "Cannot select ASCII test source")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let terminal = RecordingTerminal(frame: window.contentLayoutRect)
        window.contentView = terminal; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(terminal)
        for alternate in [false, true] {
            if alternate { terminal.feed(text: "\u{1b}[?1049h") }
            for (text, code) in [("h", UInt16(4)), ("j", 38), ("k", 40), ("l", 37), ("a", 0)] {
                terminal.bytes = []
                for index in 0..<6 {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: Double(index),
                        windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                        isARepeat: index > 0, keyCode: code)!
                    terminal.keyDown(with: event)
                }
                try require(String(decoding: terminal.bytes, as: UTF8.self) == String(repeating: text, count: 6), "Repeated letter lost: " + text)
            }
        }
        terminal.bytes = []
        terminal.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(terminal.hasMarkedText() && terminal.bytes.isEmpty, "IME preedit was transmitted prematurely")
        terminal.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(!terminal.hasMarkedText() && String(decoding: terminal.bytes, as: UTF8.self) == "中文", "IME commit failed")
        print("PASS: app-only accent-menu policy, repeated h/j/k/l/a in normal/alternate screens, IME preedit and Chinese commit")
    }
}
