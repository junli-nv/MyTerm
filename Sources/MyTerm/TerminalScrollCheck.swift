import AppKit
import SwiftTerm
import MyTermCore

/// Exercise history reading while a TUI keeps painting its live screen.
enum TerminalScrollCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Terminal scroll: " + message) }
        }
        let view = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.resize(cols: 40, rows: 12)
        view.changeScrollback(200)
        view.feed(text: (0..<160).map { "HISTORY_\($0)\r\n" }.joined())
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        let previousRow = view.getTerminal().buffer.yDisp
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: 120, wheel2: 0, wheel3: 0)!
        view.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        try require(!view.bytes.isEmpty && view.getTerminal().buffer.yDisp == previousRow,
                    "Ordinary mouse-aware terminals lost application wheel routing")
        view.bytes = []
        view.feed(text: "\u{1b}[?1000l\u{1b}[?1006l")
        view.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        try require(view.bytes.isEmpty && view.getTerminal().buffer.yDisp < previousRow,
                    "Mouse reporting disabled but wheel did not scroll local history")
        try require(view.allowMouseReporting, "Local wheel handling changed click routing")
        view.scrollUp(lines: 30)
        let buffer = view.getTerminal().buffer
        let initial = buffer.yDisp
        try require(initial > 0, "Fixture has no history")
        let text = view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true)
        for i in 0..<60 {
            view.feed(text: "\u{1b}[?2026h\u{1b}[12;1H\r\nOUTPUT_\(i)\u{1b}[K\u{1b}[?2026l")
            try require(view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true) == text,
                        "Reading anchor moved during output at chunk \(i)")
        }
        view.scroll(toPosition: 1)
        view.feed(text: "\r\nLATEST")
        try require(view.scrollPosition == 1, "Bottom did not resume following")
        view.feed(text: "\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?1006h")
        view.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        try require(!view.bytes.isEmpty, "Alternate-screen mouse reporting was disabled")
        print("PASS: terminal history anchor during synchronized output and buffer recycling; resume at bottom")
    }
}
