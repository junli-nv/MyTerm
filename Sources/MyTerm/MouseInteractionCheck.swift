#if DEBUG
import AppKit

enum MouseInteractionCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var pasteCount = 0
        var copies: [String] = []
        override func paste(_ sender: Any) { pasteCount += 1 }
        override func copy(_ sender: Any) { copies.append(selection.getSelectedText()) }
    }

    static func run(window: NSWindow) throws {
        let suite = "MyTerm.MouseCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MousePreferences(defaults: defaults)
        let terminal = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        terminal.preferences = preferences
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "MouseInteractionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0)!
        }
        var zoom = FontZoomGesture()
        try require(zoom.consume(delta: 50, inverted: false, precise: true, control: false, momentum: false, began: true, timestamp: 1) == nil, "Ordinary scrolling must pass through")
        try require(zoom.consume(delta: -20, inverted: true, precise: true, control: true, momentum: false, began: true, timestamp: 2) == 0, "Small motion must accumulate")
        try require(zoom.consume(delta: -20, inverted: true, precise: true, control: true, momentum: false, began: false, timestamp: 2.1) == 0.5, "Natural-scroll upward gesture must enlarge by half a point")
        try require(zoom.consume(delta: -500, inverted: true, precise: true, control: true, momentum: false, began: false, timestamp: 2.11) == 0, "Rapid events must be throttled")
        try require(zoom.consume(delta: 40, inverted: true, precise: true, control: true, momentum: false, began: false, timestamp: 2.3) == -0.5, "Direction reversal must shrink immediately after threshold")
        try require(zoom.consume(delta: -500, inverted: true, precise: true, control: false, momentum: true, began: false, timestamp: 2.4) == 0, "Zoom momentum must be swallowed after Ctrl release")
        try require(zoom.consume(delta: 500, inverted: false, precise: true, control: true, momentum: false, began: true, timestamp: 3) == 0.5, "Large non-natural motion must still be capped at half a point")
        print("PASS: Ctrl scroll font zoom direction, threshold, half-point cap, throttling and momentum suppression")
        try require(preferences.rightClickPastes && preferences.copyOnSelection, "Default mouse behavior")
        terminal.rightMouseDown(with: event(.rightMouseDown))
        terminal.rightMouseUp(with: event(.rightMouseUp))
        try require(terminal.pasteCount == 1, "Right click must paste exactly once")
        try require(terminal.menu(for: event(.rightMouseDown, flags: .shift))?.items.first?.title == L10n.text("复制"), "Shift right click must keep menu available")
        preferences.rightClickPastes = false
        try require(terminal.menu(for: event(.rightMouseDown)) != nil, "Disabled right-click paste must show menu")
        terminal.feed(text: "Selected text")
        terminal.selection.select(row: 0)
        terminal.mouseUp(with: event(.leftMouseUp))
        try require(terminal.copies == ["Selected text"], "Selection must be copied on mouse release")
        preferences.copyOnSelection = false
        terminal.mouseUp(with: event(.leftMouseUp))
        try require(terminal.copies.count == 1, "Disabled auto-copy must not alter clipboard")
        let reloaded = MousePreferences(defaults: UserDefaults(suiteName: suite)!)
        try require(!reloaded.rightClickPastes && !reloaded.copyOnSelection, "Mouse settings must survive reload")
        preferences.copyOnSelection = true
        terminal.selection.selectNone()
        terminal.mouseUp(with: event(.leftMouseUp))
        try require(terminal.copies.count == 1, "Empty selection must not clear clipboard")
        print("PASS: right-click paste once, context menu fallback, selection copy, switches, persistence")
    }
}
#endif
