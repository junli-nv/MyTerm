import AppKit
import SwiftTerm
import MyTermCore

/// Captured tmux/less redraws are replayed in every build, without requiring tmux on the installed Mac.
enum TerminalCopyCheck {
    struct Frame: Decodable { let name: String; let cols: Int; let rows: Int; let data: String; let expected: String }
    static func run() throws {
        let clipboard = NSPasteboard.general
        let saved = clipboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        defer {
            clipboard.clearContents()
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
            }
            if !items.isEmpty { clipboard.writeObjects(items) }
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Terminal copy: " + message) }
        }
        func doubleClick(_ view: MouseTerminalView, screenRow: Int, shift: Bool = false, counts: [Int] = [1, 2]) {
            let height = view.getOptimalFrameSize().height / CGFloat(view.getTerminal().rows)
            let point = view.convert(NSPoint(x: 5, y: view.frame.height - height * (CGFloat(screenRow) + 0.5)), to: nil)
            for count in counts {
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? [.shift] : [], timestamp: 0,
                        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
                    if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
                }
            }
        }
        let clicked = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        for alternate in [false, true] {
            clicked.resize(cols: 10, rows: 8)
            let record = "hello world: 中文 abcdefghij END"
            clicked.feed(text: (alternate ? "\u{1b}[?1049h" : "") + "\u{1b}[2J\u{1b}[H" + record + "\r\nNEXT LINE!")
            for row in 0...3 {
                clicked.selection.selectNone()
                doubleClick(clicked, screenRow: row)
                try require(clicked.selection.getSelectedText() == ["hello", "world:", "abcdefghij", "END"][row], "First double click did not select whitespace token")
                doubleClick(clicked, screenRow: row)
                try require(clicked.selection.getSelectedText() == record, "Double click missed wrapped logical line from row \(row)")
            }
            doubleClick(clicked, screenRow: 4)
            try require(clicked.selection.getSelectedText() == "NEXT", "New token must restart progressive selection")
            doubleClick(clicked, screenRow: 4, counts: [3, 4])
            try require(clicked.selection.getSelectedText() == "NEXT LINE!", "Double click crossed hard break or lost final column")
            // Mouse reporting retains ownership; Shift explicitly selects locally.
            clicked.feed(text: "\u{1b}[?1000h")
            clicked.selection.selectNone()
            doubleClick(clicked, screenRow: 1)
            try require(!clicked.selection.active, "Double click intercepted remote mouse input")
            doubleClick(clicked, screenRow: 1, shift: true)
            try require(clicked.selection.getSelectedText() == "world:", "Shift first double click missed token")
            doubleClick(clicked, screenRow: 1, shift: true)
            try require(clicked.selection.getSelectedText() == record, "Shift double click did not select locally")
            clicked.feed(text: "\u{1b}[?1000l")
        }
        clicked.feed(text: "\u{1b}[2J\u{1b}[Hhttps://host/a-b?q=中文/path\r\nseparate")
        for row in 0...2 {
            clicked.selection.selectNone()
            doubleClick(clicked, screenRow: row)
            try require(clicked.selection.getSelectedText() == "https://host/a-b?q=中文/path", "Whitespace token split at punctuation, wide cell, or soft wrap")
        }
        clicked.feed(text: "\u{1b}[2J\u{1b}[H　token")
        for col in [0, 1] {
            clicked.selection.selectWhitespaceWord(at: Position(col: col, row: 0), in: clicked.getTerminal().buffer)
            try require(clicked.selection.getSelectedText() == "　", "Full-width whitespace boundary was split")
        }
        print("PASS: progressive double clicks: whitespace tokens, punctuation, CJK, soft wraps, repeat/quad click and remote mouse routing")
        let view = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let streaming = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        streaming.resize(cols: 40, rows: 12)
        streaming.feed(text: (0...7).map { "KEEP_\($0)\r\n" }.joined())
        let lineHeight = streaming.getOptimalFrameSize().height / 12
        func drag(_ row: Int) {
            let point = streaming.convert(NSPoint(x: 5, y: streaming.frame.height - lineHeight * (CGFloat(row) + 0.5)), to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDragged, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            streaming.mouseDragged(with: event)
        }
        try require(streaming.allowMouseReporting && streaming.getTerminal().mouseMode == .off, "Streaming test must use default mouse routing")
        drag(1)
        try require(streaming.selection.active, "First drag did not activate selection")
        let viewport = streaming.getTerminal().buffer.yDisp
        for chunk in 0..<20 {
            streaming.feed(text: "OUTPUT_\(chunk)\r\n")
            try require(streaming.selection.active, "Feed cleared selection at chunk \(chunk)")
            drag(3)
            try require(streaming.selection.active && streaming.selection.getSelectedText().trimmingCharacters(in: .newlines) == "KEEP_1\nKEEP_2", "Streaming chunk \(chunk): \(streaming.selection.debugDescription), viewport \(streaming.getTerminal().buffer.yDisp), text \(streaming.selection.getSelectedText().debugDescription)")
        }
        try require(streaming.getTerminal().buffer.yDisp == viewport, "Output moved viewport during selection")
        try require(String(decoding: streaming.getTerminal().getBufferAsData(), as: UTF8.self).contains("OUTPUT_19"), "Selecting paused process output")
        streaming.copy(streaming)
        try require(clipboard.string(forType: .string)?.trimmingCharacters(in: .newlines) == "KEEP_1\nKEEP_2", "Copy failed while output was streaming")
        streaming.selection.selectNone()
        streaming.scroll(toPosition: 1)
        let bottom = streaming.getTerminal().buffer.yDisp
        streaming.feed(text: "FOLLOW_AGAIN\r\n")
        try require(streaming.getTerminal().buffer.yDisp > bottom, "Scrolling to bottom did not resume output following")
        // Full-screen applications may report mouse events. Shift-created local
        // selections must also survive redraws elsewhere in their screen.
        streaming.selection.select(row: streaming.getTerminal().buffer.yDisp)
        streaming.feed(text: "\u{1b}[?1049h\u{1b}[HKEEP\r\n\u{1b}[?1000h")
        try require(!streaming.selection.active, "Switching buffers retained an unrelated selection")
        streaming.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 4, row: 0))
        for _ in 0..<10 { streaming.feed(text: "\u{1b}[3;1Hworking\u{1b}[K") }
        try require(streaming.selection.active && streaming.selection.getSelectedText() == "KEEP", "Full-screen updates erased a local selection")
        print("PASS: streaming selection: interleaved mouse drag/output, stable history viewport, clipboard, continued output, resume following and full-screen redraw")
        view.resize(cols: 10, rows: 8)
        view.feed(text: "1234567890abcdef")
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 6, row: 1))
        view.copy(view)
        try require(clipboard.string(forType: .string) == "1234567890abcdef", "Normal-shell soft wrap must still join")
        view.feed(text: "\u{1b}[?1049h\u{1b}[H1234567890abcdef")
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 6, row: 1))
        view.copy(view)
        try require(clipboard.string(forType: .string) == "1234567890abcdef", "Full-screen soft wraps must join")
        view.copyPreservingScreenLines(view)
        try require(clipboard.string(forType: .string) == "1234567890\nabcdef", "Explicit screen-row copying is unavailable")
        view.feed(text: "\u{1b}[2J\u{1b}[Hone\r\n\r\n中文\r\nthree")
        view.selection.setSelection(start: Position(col: 5, row: 3), end: Position(col: 0, row: 0))
        view.copy(view)
        try require(clipboard.string(forType: .string) == "one\n\n中文\nthree", "Hard breaks, blank rows, Unicode or reverse selection lost")
        view.selection.selectNone()
        view.feed(text: "\u{1b}[2J\u{1b}[H123456789012345678901234567890")
        view.feed(text: "\u{1b}[1;1Hone\u{1b}[K\u{1b}[2;1Htwo\u{1b}[K\u{1b}[3;1Hthree\u{1b}[K")
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 2))
        try require(view.selection.getSelectedText() == "one\ntwo\nthree", "Redraw left stale wrap flags")
        view.copy(view)
        try require(clipboard.string(forType: .string) == "one\ntwo\nthree", "Redrawn short lines were joined")
        // Filling a row exactly followed by CRLF must remain a hard break.
        view.selection.selectNone()
        view.feed(text: "\u{1b}[2J\u{1b}[H1234567890\r\nABCDEFGHIJ\r\nend")
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 3, row: 2))
        view.copy(view)
        try require(clipboard.string(forType: .string) == "1234567890\nABCDEFGHIJ\nend", "Full-width hard newline was joined")
        // Real font changes invoke the terminal's resize/reflow path.
        let zoom = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        let paragraph = String(repeating: "abc中文DEF ", count: 30) + "END"
        zoom.feed(text: paragraph + "\r\nsecond logical line")
        var widths = Set<Int>()
        for size in [13.0, 22.0, 30.0, 13.0] {
            zoom.selection.selectNone()
            zoom.font = .monospacedSystemFont(ofSize: size, weight: .regular)
            widths.insert(zoom.getTerminal().cols)
            zoom.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 0, row: Int.max))
            zoom.copy(zoom)
            try require((clipboard.string(forType: .string) ?? "").trimmingCharacters(in: .newlines) == paragraph + "\nsecond logical line", "Font zoom changed copied logical lines at \(size)")
            zoom.selection.selectNone()
            doubleClick(zoom, screenRow: 1)
            let token = zoom.selection.getSelectedText()
            try require(!token.isEmpty && paragraph.contains(token) && token != paragraph, "Zoomed first double click failed")
            doubleClick(zoom, screenRow: 1)
            try require(zoom.selection.getSelectedText() == paragraph, "Double click after font zoom missed logical line at \(size)")
        }
        try require(widths.count >= 3, "Font test did not resize the grid")
        let replay = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var dimensions = (0, 0)
        var joinedStages: [String] = []
        for frame in try JSONDecoder().decode([Frame].self, from: Data(base64Encoded: TmuxLessCopyFixture.data)!) {
            replay.selection.selectNone() // End the previous copy before the next less repaint.
            if dimensions != (frame.cols, frame.rows) { replay.resize(cols: frame.cols, rows: frame.rows); dimensions = (frame.cols, frame.rows) }
            replay.feed(byteArray: Array(Data(base64Encoded: frame.data)!)[...])
            let top = replay.getTerminal().buffer.yDisp
            replay.selection.setSelection(start: Position(col: 0, row: top), end: Position(col: 0, row: top + frame.rows - 1))
            let before = replay.getTerminal().getBufferAsData()
            replay.copy(replay)
            let logical = (clipboard.string(forType: .string) ?? "").trimmingCharacters(in: .newlines)
            // These captures emit autowrap/CRLF. The known fixture contains
            // 88-column LONG records and short Chinese records, never hard
            // breaks at the grid width. Build an independent plaintext oracle.
            if ["initial-long-lines", "page-down", "page-down-again", "search-short-lines", "resize"].contains(frame.name) {
                let rows = frame.expected.components(separatedBy: "\n")
                var expected = ""
                for (index, row) in rows.enumerated() {
                    if index > 0 && rows[index - 1].count != frame.cols { expected += "\n" }
                    expected += row
                }
                try require(logical == expected, "tmux/less default copy \(frame.name): expected \(expected.debugDescription), got \(logical.debugDescription)")
            }
            replay.copyPreservingScreenLines(replay)
            let actual = (clipboard.string(forType: .string) ?? "").trimmingCharacters(in: .newlines)
            try require(actual == frame.expected, "tmux/less \(frame.name): expected \(frame.expected.debugDescription), got \(actual.debugDescription)")
            try require(replay.getTerminal().getBufferAsData() == before, "Copy modified the rendered buffer")
            if logical != actual { joinedStages.append(frame.name) }
        }
        try require(!joinedStages.isEmpty, "Fixture did not exercise row joining")
        print("PASS: clipboard: normal/full-screen soft wraps, hard breaks, stale wrap invalidation, font zoom reflow, screen-row copy; real tmux/less page/search/resize replay (\(joinedStages.joined(separator: ", ")))")
    }
}
