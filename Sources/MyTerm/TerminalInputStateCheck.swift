import AppKit
import Carbon.HIToolbox
import SwiftTerm
import MyTermCore

/// Exercise terminal state transitions without contacting a model or SSH host.
enum TerminalInputStateCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }
    static func run() throws {
        var failures = [String]()
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        let view = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.resize(cols: 40, rows: 12)
        view.feed(text: "first\r\nsecond")
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
        view.feed(text: " progress")
        check(view.selection.active, "Output cleared local selection")
        view.selection.selectNone()
        view.send(txt: "x")
        view.feed(text: String(repeating: "\r\noutput", count: 30))
        check(view.scrollPosition == 1, "Output failed to follow after resumed input")

        let emptyRange = NSRange(location: NSNotFound, length: 0)
        // A committed preedit in legacy mode must not suppress keys after a TUI
        // subsequently negotiates the enhanced keyboard protocol.
        for emptyPreedit in [false, true] {
            let input = RecordingTerminal(frame: view.frame)
            input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: emptyRange)
            check(input.bytes.isEmpty && input.hasMarkedText(), "Preedit was sent before commit")
            if emptyPreedit {
                input.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: emptyRange)
            } else {
                input.insertText("中", replacementRange: emptyRange)
                check(String(decoding: input.bytes, as: UTF8.self) == "中", "Committed Chinese text changed")
            }
            check(!input.hasMarkedText(), "Preedit did not end")
            input.feed(text: "\u{1b}[>8u") // report-all-keys, including Enter
            input.bytes = []
            input.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            check(String(decoding: input.bytes, as: UTF8.self) == "\u{1b}[13u", "Enter encoding retained stale composition state (empty=\(emptyPreedit)): \(input.bytes)")
        }
        guard let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
            throw ConfigurationError.invalid("ASCII input source unavailable")
        }
        defer { TISSelectInputSource(original) }
        check(TISSelectInputSource(ascii) == noErr, "Cannot select ASCII input source")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for flags in [0, 1, 3, 8, 11] {
            let input = RecordingTerminal(frame: view.frame)
            window.contentView = input; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input)
            for alternate in [false, true] {
                if alternate { input.feed(text: "\u{1b}[?1049h") }
                if flags != 0 { input.feed(text: "\u{1b}[>\(flags)u") }
                input.bytes = []
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                        isARepeat: false, keyCode: 36)!
                    if type == .keyDown { input.keyDown(with: event) } else { input.keyUp(with: event) }
                    if type == .keyDown {
                        let expected = flags & 8 == 0 ? "\r" : "\u{1b}[13u"
                        check(String(decoding: input.bytes, as: UTF8.self) == expected, "First Return lost or duplicated (flags=\(flags), alternate=\(alternate)): \(input.bytes)")
                    }
                }
            }
        }
        if !failures.isEmpty { throw ConfigurationError.invalid("Terminal input state: " + failures.joined(separator: "; ")) }
        print("PASS: terminal follow resumes on input with visible cursor; committed/empty IME state and single Enter encoding")
    }
}
