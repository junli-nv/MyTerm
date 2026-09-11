import AppKit
import SwiftTerm
import MyTermCore

enum OutputHighlightCheck {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Output highlight: " + message) }
        }
        var config = OutputHighlightConfiguration()
        let terminalView = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 700, height: 240))
        let terminal = terminalView.getTerminal()
        let window = NSWindow(contentRect: terminalView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = terminalView; window.orderFront(nil)
        defer { window.close() }
        window.layoutIfNeeded()
        let columns = terminal.cols
        for byte in Array("Error up inactive backup \u{1b}[34merror\u{1b}[0m ok".utf8) {
            terminalView.dataReceived(slice: [byte][...])
        }
        let line = terminal.bufferLine(atRow: 0)!
        let raw = terminal.getBufferAsData(), cursor = terminal.getCursorLocation()
        let attributes = (0..<columns).map { line[$0].attribute }
        let highlighter = try TerminalOutputHighlighter(config)
        let colors = highlighter.colors(terminal: terminal, row: 0, line: line, columns: columns, isSSH: true)
        try require(colors[0] == .trueColor(red: 239, green: 83, blue: 80), "Error was not red")
        try require(colors[6] == .trueColor(red: 76, green: 175, blue: 80), "up was not green")
        try require(colors[9] == nil && colors[18] == nil && colors[25] == nil, "Boundary or ANSI preservation failed")
        try require(highlighter.colors(terminal: terminal, row: 0, line: line, columns: columns, isSSH: false).isEmpty, "Local shell should be opt-in")
        var renderCalls = 0
        terminalView.rowForegroundProvider = { row, line, cols in
            renderCalls += 1
            return highlighter.colors(terminal: terminal, row: row, line: line, columns: cols, isSSH: true)
        }
        if let bitmap = terminalView.bitmapImageRepForCachingDisplay(in: terminalView.bounds) {
            terminalView.cacheDisplay(in: terminalView.bounds, to: bitmap)
        }
        try require(renderCalls > 0, "Native renderer did not invoke foreground provider")
        try require(terminal.getBufferAsData() == raw && (0..<columns).map({ line[$0].attribute }) == attributes,
                    "Rendering modified original text or ANSI attributes")
        try require(terminal.getCursorLocation().x == cursor.x && terminal.getCursorLocation().y == cursor.y, "Rendering moved cursor")
        config.preserveANSI = false
        try require(try TerminalOutputHighlighter(config).colors(terminal: terminal, row: 0, line: line, columns: columns, isSSH: true)[25] != nil, "Explicit ANSI override failed")

        // A keyword can straddle soft-wrapped rows; packet/row boundaries are not word boundaries.
        let wrapped = MouseTerminalView(frame: .zero).getTerminal()
        wrapped.resize(cols: 8, rows: 4)
        wrapped.feed(buffer: Array("12345 Error".utf8)[...])
        let first = wrapped.bufferLine(atRow: 0)!, second = wrapped.bufferLine(atRow: 1)!
        try require(highlighter.colors(terminal: wrapped, row: 0, line: first, columns: 8, isSSH: true)[6] != nil,
                    "Soft-wrapped keyword start missing")
        try require(highlighter.colors(terminal: wrapped, row: 1, line: second, columns: 8, isSSH: true)[0] != nil,
                    "Soft-wrapped keyword end missing")
        terminal.feed(buffer: Array("\r\u{1b}[2Kok".utf8)[...])
        try require(highlighter.colors(terminal: terminal, row: 0, line: line, columns: columns, isSSH: true)[0] == .trueColor(red: 76, green: 175, blue: 80), "CR/erase left stale colors")
        terminal.feed(buffer: Array("\u{1b}[?1049hError".utf8)[...])
        let alternate = terminal.bufferLine(atRow: 0)!
        try require(highlighter.colors(terminal: terminal, row: 0, line: alternate, columns: columns, isSSH: true).isEmpty, "Alternate screen should be opt-in")
        config.includeAlternate = true
        try require(!TerminalOutputHighlighter(config).colors(terminal: terminal, row: 0, line: alternate, columns: columns, isSSH: true).isEmpty, "Alternate screen opt-in failed")
        terminal.feed(buffer: Array("\u{1b}[?1049l".utf8)[...])
        let encoded = MouseTerminalView(frame: .zero)
        try encoded.setEncoding(.gbk)
        let transcoder = try TerminalTranscoder(from: .utf8, to: .gbk)
        for byte in transcoder.convert(Array("中文 Error".utf8)) { encoded.dataReceived(slice: [byte][...]) }
        let model = encoded.getTerminal(), decoded = model.bufferLine(atRow: 0)!
        try require(highlighter.colors(terminal: model, row: 0, line: decoded, columns: model.cols, isSSH: true).count == 5, "GBK/CJK cell mapping failed")
        let defaults = UserDefaults(suiteName: "MyTerm.HighlightCheck.\(UUID())")!
        let preferences = OutputHighlightPreferences(defaults: defaults)
        encoded.configureOutputHighlighting(isSSH: true, preferences: preferences)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try require(encoded.rowForegroundProvider?(0, decoded, model.cols).count == 5, "Initial live configuration failed")
        preferences.configuration.enabled = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try require((encoded.rowForegroundProvider?(0, decoded, model.cols) ?? [:]).isEmpty, "Live disable failed")
        print("PASS: output highlight: renderer invocation, raw text/ANSI/cursor preservation, byte chunks, soft wrap, CR/erase, alternate screen, GBK/CJK and live settings")
    }
}
