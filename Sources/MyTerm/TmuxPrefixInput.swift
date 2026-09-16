import AppKit
import Carbon.HIToolbox

/// Translate only the default tmux prefix and its next printable key. Normal
/// text continues through the input method, and we never switch the system IME.
struct TmuxPrefixInput {
    private(set) var awaitingCommand = false
    mutating func reset() { awaitingCommand = false }

    mutating func consume(_ event: NSEvent) -> String? {
        let pending = awaitingCommand
        awaitingCommand = false
        let flags = event.modifierFlags.intersection([.control, .command, .option, .shift])
        guard !flags.contains(.command), !flags.contains(.option) else { return nil }
        guard pending || flags == .control else { return nil }
        let ascii = Self.asciiText(event)
        if flags == .control && ascii?.lowercased() == "b" {
            // A second prefix sends literal Ctrl+B, without arming a third key.
            awaitingCommand = !pending
            return "\u{02}"
        }
        guard pending, !flags.contains(.control), let ascii, !ascii.isEmpty,
              ascii.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { return nil }
        return ascii
    }

    static func asciiText(_ event: NSEvent) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var count = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let modifiers = event.modifierFlags.contains(.shift) ? UInt32(shiftKey >> 8) : 0
        let result = UCKeyTranslate(layout, event.keyCode, UInt16(kUCKeyActionDown), modifiers,
                                    UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                    &deadKey, characters.count, &count, &characters)
        guard result == noErr else { return nil }
        return String(utf16CodeUnits: characters, count: count)
    }
}
