import AppKit
import MyTermCore

enum TmuxPrefixInputCheck {
    static func run() throws {
        func event(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: text,
                             charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Tmux input: " + message) }
        }
        var input = TmuxPrefixInput()
        let prefix = event(11, "b", .control), bracket = event(33, "【")
        try require(input.consume(bracket) == nil, "Normal Chinese punctuation intercepted")
        try require(input.consume(prefix) == "\u{02}", "Ctrl+B prefix was not sent")
        try require(input.consume(bracket) == TmuxPrefixInput.asciiText(bracket), "Prefix command did not use ASCII layout")
        try require(!input.awaitingCommand && input.consume(bracket) == nil, "IME did not resume after command")
        _ = input.consume(prefix)
        let percent = event(23, "％", .shift)
        try require(input.consume(percent) == TmuxPrefixInput.asciiText(percent), "Shift command lost its modifier")
        _ = input.consume(prefix)
        try require(input.consume(prefix) == "\u{02}" && !input.awaitingCommand, "Double prefix rearmed translation")
        _ = input.consume(prefix); input.reset()
        try require(input.consume(bracket) == nil, "Focus change retained prefix")
        _ = input.consume(prefix)
        try require(input.consume(event(33, "【", .command)) == nil && !input.awaitingCommand, "Command shortcut intercepted")
        _ = input.consume(prefix)
        try require(input.consume(event(123, "\u{f702}")) == nil, "Arrow key bypassed terminal handling")
        print("PASS: tmux prefix ASCII commands, Chinese text preservation, Shift, literal prefix and focus reset")
    }
}
