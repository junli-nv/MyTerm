import AppKit
import SwiftTerm
import MyTermCore

enum FullscreenScrollCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }
    static func run() throws {
        let suite = "MyTerm.ScrollCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MousePreferences(defaults: defaults)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Trackpad scrolling: " + message) }
        }
        var pages = FullscreenScrollGesture()
        try require(preferences.fullscreenScroll == .fast, "Default fast scrolling")
        try require(pages.page(delta: 20, began: true, momentum: false, timestamp: 1) == 0, "Small gesture must accumulate")
        try require(pages.page(delta: 30, began: false, momentum: false, timestamp: 1.1) == 1, "Page up after threshold")
        try require(pages.page(delta: 500, began: false, momentum: false, timestamp: 1.11) == 0, "Throttle page flood")
        try require(pages.page(delta: 10, began: false, momentum: false, timestamp: 1.3) == 1, "Sustained scrolling continues")
        try require(pages.page(delta: -50, began: false, momentum: false, timestamp: 1.31) == -1, "Reverse direction promptly")
        try require(pages.page(delta: 500, began: false, momentum: true, timestamp: 2) == 0, "Ignore momentum")
        preferences.fullscreenScroll = .pages
        try require(MousePreferences(defaults: defaults).fullscreenScroll == .pages, "Scroll preference persistence")
        print("PASS: full-screen trackpad modes, page threshold, throttle, reversal, momentum and persistence")

        let terminal = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        terminal.preferences = preferences
        func wheel(_ delta: Int32, precise: Bool = true) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                             wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
            return NSEvent(cgEvent: cg)!
        }
        terminal.feed(text: "\u{1b}[?1049h\u{1b}[?1007h")
        terminal.scrollWheel(with: wheel(60))
        try require(String(decoding: terminal.bytes, as: UTF8.self) == "\u{1b}[5~", "Page Up bytes")
        terminal.bytes = []
        terminal.scrollWheel(with: wheel(-60))
        try require(String(decoding: terminal.bytes, as: UTF8.self) == "\u{1b}[6~", "Page Down bytes")
        preferences.fullscreenScroll = .standard; terminal.bytes = []
        terminal.scrollWheel(with: wheel(120))
        let standardCount = terminal.bytes.count
        preferences.fullscreenScroll = .fast; terminal.bytes = []
        terminal.scrollWheel(with: wheel(120))
        try require(standardCount > 0 && terminal.bytes.count > standardCount * 2, "Fast mode must send more navigation events")
        try require(terminal.scrollSensitivity == 1, "Fast mode leaked into ordinary scrolling")
        preferences.fullscreenScroll = .pages; terminal.bytes = []
        terminal.scrollWheel(with: wheel(1, precise: false))
        try require(!String(decoding: terminal.bytes, as: UTF8.self).contains("[5~"), "Mouse wheel incorrectly paged")
        terminal.feed(text: "\u{1b}[?1049l"); terminal.bytes = []
        terminal.scrollWheel(with: wheel(120))
        try require(terminal.bytes.isEmpty, "Normal shell received page keys")
        print("PASS: actual trackpad events: page key encoding, accelerated full-screen navigation, standard shell and mouse-wheel isolation")
    }
}
