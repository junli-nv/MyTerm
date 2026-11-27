import AppKit
import SwiftTerm
import MyTermCore

/// Preserve the entire reported interaction, including copy-mode repaint and
/// both clicks. A screen-text assertion alone cannot catch lost wrap selection.
enum TerminalSelectionCheck {
    private struct Frame: Decodable {
        let name: String, data: String, expected: String
        let cols: Int, rows: Int, targetRow: Int
    }
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Terminal selection: " + message) }
        }
        func click(_ view: MouseTerminalView, row: Int, counts: [Int] = [1, 2], shift: Bool = false, holdLastPress: Bool = false) {
            let h = view.getOptimalFrameSize().height / CGFloat(view.getTerminal().rows)
            let point = view.convert(NSPoint(x: 5, y: view.frame.height - h * (CGFloat(row) + 0.5)), to: nil)
            for count in counts {
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    if holdLastPress && count == counts.last && type == .leftMouseUp { continue }
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? .shift : [], timestamp: 0,
                        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
                    if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
                }
            }
        }
        let view = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let frames = try JSONDecoder().decode([Frame].self, from: Data(base64Encoded: TmuxCopyModeFixture.data, options: .ignoreUnknownCharacters)!)
        var checked = [String]()
        for frame in frames {
            view.selection.selectNone()
            if view.getTerminal().cols != frame.cols || view.getTerminal().rows != frame.rows {
                view.resize(cols: frame.cols, rows: frame.rows)
            }
            view.feed(byteArray: Array(Data(base64Encoded: frame.data)!)[...])
            if ["initial", "copy-mode"].contains(frame.name) { continue }
            let before = view.getTerminal().getBufferAsData()
            let wrapFlags = (0..<frame.rows).map { view.getTerminal().getLine(row: $0)?.isWrapped }
            let word = String(frame.expected.split(separator: " ")[0])
            click(view, row: frame.targetRow)
            try require(view.selection.getSelectedText() == word, "\(frame.name): first double-click expected \(word), got \(view.selection.getSelectedText().debugDescription); row \(frame.targetRow): \(view.getTerminal().getLine(row: frame.targetRow)?.translateToString(trimRight: true) ?? "missing")")
            click(view, row: frame.targetRow)
            let selected = view.selection.getSelectedText()
            try require(selected == frame.expected,
                "\(frame.name): repeated double-click missed wrapped record: \(selected.debugDescription)")
            view.copy(view)
            try require(NSPasteboard.general.string(forType: .string) == frame.expected, "\(frame.name): clipboard differs from logical selection")
            view.copyPreservingScreenLines(view)
            try require((NSPasteboard.general.string(forType: .string) ?? "").components(separatedBy: "\n").count == 3,
                        "\(frame.name): screen-line copy no longer preserves visual rows")
            try require(view.getTerminal().getBufferAsData() == before, "Selection modified terminal contents")
            view.selection.selectNone()
            view.feed(text: "\u{1b}[?1000h")
            click(view, row: frame.targetRow)
            try require(!view.selection.active, "\(frame.name): intercepted remote mouse click")
            click(view, row: frame.targetRow, shift: true)
            try require(view.selection.getSelectedText() == word, "\(frame.name): Shift token selection failed")
            click(view, row: frame.targetRow, shift: true)
            try require(view.selection.getSelectedText() == frame.expected, "\(frame.name): Shift logical selection failed")
            view.copy(view)
            try require(NSPasteboard.general.string(forType: .string) == frame.expected, "\(frame.name): Shift clipboard mismatch")
            view.feed(text: "\u{1b}[?1000l")
            view.selection.selectNone()
            click(view, row: frame.targetRow + 1)
            let wrappedWord = String(frame.expected.split(separator: " ")[1])
            try require(view.selection.getSelectedText() == wrappedWord, "\(frame.name): wrapped token split at visual edge")
            view.copy(view)
            try require(NSPasteboard.general.string(forType: .string) == wrappedWord, "\(frame.name): wrapped token clipboard mismatch")
            click(view, row: frame.targetRow + 1)
            try require(view.selection.getSelectedText() == frame.expected, "\(frame.name): logical row from middle failed")
            view.selection.selectNone()
            click(view, row: frame.targetRow)
            click(view, row: frame.targetRow, holdLastPress: true)
            let height = view.getOptimalFrameSize().height / CGFloat(frame.rows)
            let point = view.convert(NSPoint(x: 5, y: view.frame.height - height * (CGFloat(frame.targetRow + 4) + 0.5)), to: nil)
            for type: NSEvent.EventType in [.leftMouseDragged, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
                if type == .leftMouseDragged { view.mouseDragged(with: event) } else { view.mouseUp(with: event) }
            }
            let nextID = Int(word.dropFirst("RECORD_".count))! + 1
            let nextRecord = String(format: "RECORD_%03d", nextID) + String(frame.expected.dropFirst(word.count))
            let records = frame.expected + "\n" + nextRecord
            try require(view.selection.getSelectedText() == records, "\(frame.name): row drag lost hard record boundary: \(view.selection.getSelectedText().debugDescription), \(view.selection.debugDescription), mode=\(view.selection.selectionMode)")
            view.copy(view)
            try require(NSPasteboard.general.string(forType: .string) == records, "\(frame.name): row drag clipboard differs")
            try require(view.getTerminal().getBufferAsData() == before, "Row drag changed terminal cells")
            try require((0..<frame.rows).map { view.getTerminal().getLine(row: $0)?.isWrapped } == wrapFlags, "Selection changed native wrap flags")
            checked.append(frame.name)
        }
        try require(checked.count == 5, "Missing copy-mode paging/scroll stages")
        for text in ["hello     next", "hello     next   ", "abcdefghi中suffix", "https://host/中文/path"] {
            let native = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            native.resize(cols: 10, rows: 8)
            native.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[H" + text + "\r\nseparate")
            click(native, row: 0)
            click(native, row: 0)
            try require(native.selection.getSelectedText() == text, "Fallback broke native blank/wide wrap")
        }
        let hard = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        hard.resize(cols: 10, rows: 6)
        hard.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[Habcdefghij\r\nklmnopqrst")
        click(hard, row: 0)
        try require(hard.selection.getSelectedText() == "abcdefghij", "Native exact-width hard break merged tokens")
        click(hard, row: 0)
        try require(hard.selection.getSelectedText() == "abcdefghij", "Native exact-width hard break merged logical rows")
        hard.selection.dragExtend(row: 1, col: 0)
        hard.copy(hard)
        try require(NSPasteboard.general.string(forType: .string) == "abcdefghij\nklmnopqrst", "Native row drag lost exact-width hard break")
        // A double-width glyph that cannot fit in the last column leaves a
        // one-cell gap. Repaint preserves the gap but sends no native wrap.
        let wideRepaint = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        wideRepaint.resize(cols: 10, rows: 6)
        wideRepaint.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[Habcdefghi\u{1b}[2;1H中suffix")
        click(wideRepaint, row: 0)
        try require(wideRepaint.selection.getSelectedText() == "abcdefghi中suffix", "Coordinate repaint split a wide-character edge gap")
        click(wideRepaint, row: 0)
        wideRepaint.copy(wideRepaint)
        try require(NSPasteboard.general.string(forType: .string) == "abcdefghi中suffix", "Wide repaint clipboard lost logical row")
        // Coordinate-painted screens: reject visual evidence of independent
        // rows. These boundaries are not recovered from the implementation.
        for (label, top, bottom, style) in [
            ("short hard line", "short", "second", ""),
            ("pane border", "aaaa│bbbbb", "cccc│ddddd", ""),
            ("table border", "aaaa|bbbbb", "cccc|ddddd", ""),
            ("styled status", "abcdefghij", "STATUS", "\u{1b}[7m")
        ] {
            let isolated = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            isolated.resize(cols: 10, rows: 6)
            isolated.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[H" + top + "\u{1b}[2;1H" + style + bottom + "\u{1b}[0m")
            click(isolated, row: 0)
            click(isolated, row: 0)
            try require(isolated.selection.getSelectedText() == top, "Logical selection crossed \(label)")
            isolated.copy(isolated)
            try require(NSPasteboard.general.string(forType: .string) == top, "Clipboard crossed \(label)")
        }
        print("PASS: native whitespace/wide wraps, coordinate-painted wide edge gap; hard-line, pane/table and status isolation")
        // Separators are tested as rendered cells, including HT-expanded gaps
        // and both cells of wide blank glyphs, rather than source-string splitting.
        view.resize(cols: 80, rows: 6)
        let separators = [" ", "\t", "\u{00a0}", "\u{1680}",
            "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}",
            "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200a}", "\u{202f}", "\u{205f}", "\u{3000}",
            "\u{115f}", "\u{2800}", "\u{3164}", "\u{ffa0}"]
        for separator in separators {
            view.selection.selectNone()
            view.feed(text: "\u{1b}[?1049l\u{1b}[2J\u{1b}[Hleft" + separator + "right")
            let terminal = view.getTerminal()
            let right = (5..<40).first { column in
                terminal.bufferLine(atRow: 0).map { terminal.getCharacter(for: $0[column]) == "r" } ?? false
            }
            // Resolve the visible 'r' without assuming a tab width or Unicode cell width.
            guard let right else { throw ConfigurationError.invalid("Missing right-hand separator fixture token") }
            for col in [0, 1, 2, 3] {
                view.selection.selectWhitespaceWord(at: Position(col: col, row: 0), in: terminal.buffer)
                try require(view.selection.getSelectedText() == "left", "Blank delimiter joined left/right tokens")
            }
            view.selection.selectWhitespaceWord(at: Position(col: right, row: 0), in: terminal.buffer)
            try require(view.selection.getSelectedText() == "right", "Blank delimiter joined right token")
            for col in 4..<right {
                view.selection.selectWhitespaceWord(at: Position(col: col, row: 0), in: terminal.buffer)
                let selected = view.selection.getSelectedText()
                try require(!selected.contains("left") && !selected.contains("right"), "Blank/wide continuation cell selected adjacent token")
            }
        }
        view.feed(text: "\u{1b}[2J\u{1b}[Hpre👩‍💻post suffix")
        view.selection.selectWhitespaceWord(at: Position(col: 0, row: 0), in: view.getTerminal().buffer)
        try require(view.selection.getSelectedText() == "pre👩‍💻post", "Split an emoji joiner/grapheme as whitespace")
        print("PASS: actual tmux copy-mode \(checked.joined(separator: ", ")): token → logical row → clipboard, row-drag hard breaks; tab/Unicode/blank-glyph delimiters and emoji preservation")
    }
}
