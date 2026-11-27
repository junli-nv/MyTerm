import AppKit
import SwiftTerm
import MyTermCore

enum CodexReplayCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var bytes: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    }
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Codex history replay: " + message) }
        }
        let view = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.45)
        view.usesApplicationScrolling = true
        view.resize(cols: 40, rows: 12); view.changeScrollback(2000)
        func feed(_ text: String) { view.dataReceived(slice: Array(text.utf8)[...]) }
        func rows(_ range: Range<Int>) -> String { range.map { "REPLAY_\($0)\r\n" }.joined() }
        func backgroundAlpha() throws -> CGFloat {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw ConfigurationError.invalid("Could not capture replay presentation")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let sampleX = min(Int(view.getOptimalFrameSize().width * 0.5 * scale), bitmap.pixelsWide - 1)
            guard let color = bitmap.colorAt(x: sampleX, y: min(40, bitmap.pixelsHigh - 1)) else {
                throw ConfigurationError.invalid("Missing replay presentation sample")
            }
            return color.alphaComponent
        }
        func readingMask() throws -> Data {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                  bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4, !bitmap.isPlanar,
                  let pixels = bitmap.bitmapData else { throw ConfigurationError.invalid("Unsupported reading bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let width = min(bitmap.pixelsWide, Int((view.getOptimalFrameSize().width - 25) * scale))
            var mask = Data(capacity: width * bitmap.pixelsHigh)
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<width {
                    let p = pixels + y * bitmap.bytesPerRow + x * 4
                    mask.append(max(max(p[0], p[1]), max(p[2], p[3])) > 32 ? 1 : 0)
                }
            }
            return mask
        }
        let clear = "\u{1b}[3J\u{1b}[2J\u{1b}[H"
        feed(rows(0..<1000)); view.scrollTo(row: 933)
        let oldLine = view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true)
        let originalAlpha = try backgroundAlpha()
        let originalMask = try readingMask()
        feed(clear)
        try require(view.getTerminal().scrollbackRowCount == 0 && view.getTerminal().buffer.yDisp == 0,
                    "CSI 3J was ignored instead of clearing the real buffer")
        try require(view.scrollbackReplay.isHolding, "Lost reading position on a clear before replay")
        try require(view.scrollbackReplay.hasReadingImage, "No reading image while the buffer is empty")
        let heldAlpha = try backgroundAlpha()
        try require(abs(heldAlpha - originalAlpha) < 0.02 && abs((view.layer?.backgroundColor?.alpha ?? 0) - 0.45) < 0.02,
                    "Reading image transparency changed (\(originalAlpha) -> \(heldAlpha))")
        feed(rows(0..<400))
        try require(view.scrollbackReplay.isHolding, "Partial replay exposed the beginning of history")
        let heldMask = try readingMask()
        let foreground = originalMask.filter { $0 != 0 }.count
        let differences = zip(originalMask, heldMask).filter { $0 != $1 }.count
        try require(foreground > 100 && originalMask.count == heldMask.count && differences <= max(5, foreground / 50),
                    "Partial replay changed the visible reading image (\(differences) changed pixels / \(foreground) foreground pixels)")
        view.scrollHistory(lines: 3)
        feed(clear) // A second clear must retain the original reading anchor.
        for start in stride(from: 0, to: 1000, by: 25) { feed(rows(start..<min(start + 25, 1000))) }
        try require(!view.scrollbackReplay.isHolding && view.getTerminal().buffer.yDisp == 930,
                    "Replay lost the original anchor or queued wheel intent")
        try require(view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true) == "REPLAY_930",
                    "Restored the wrong reading content")
        try require(oldLine == "REPLAY_933" && !view.scrollbackReplay.hasReadingImage, "Reading image survived restoration")
        feed(rows(1000..<1050))
        try require(view.getTerminal().buffer.yDisp == 930 && view.bytes.isEmpty, "New output moved history or sent remote navigation")
        // Consolidation can remove earlier rendered lines. Restore content,
        // rather than blindly reusing the old numerical viewport row.
        feed(clear); feed(rows(7..<1050))
        try require(!view.scrollbackReplay.isHolding && view.getTerminal().buffer.yDisp == 923,
                    "Changed replay length did not relocate the content anchor")
        try require(view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true) == "REPLAY_930",
                    "Reflow restored the row number instead of the reading content")
        // Returning to bottom and clearing there must retain normal output follow.
        view.scroll(toPosition: 1); feed(clear)
        try require(!view.scrollbackReplay.isHolding, "Following output was unnecessarily frozen")
        feed(rows(0..<1000))
        try require(view.scrollPosition == 1, "Bottom no longer followed replayed output")
        // A genuine clear/new transcript is bounded, even without matching text.
        view.scrollTo(row: 200); feed(clear); feed("A replacement transcript")
        try require(view.scrollbackReplay.isHolding, "Missing unmatched-replay hold")
        let timeout = Date().addingTimeInterval(2.8)
        while view.scrollbackReplay.isHolding && Date() < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try require(!view.scrollbackReplay.isHolding && view.getTerminal().buffer.yDisp == 0, "Unmatched clear froze the view indefinitely")
        feed(rows(0..<1000)); view.scrollTo(row: 100); feed(clear)
        feed("\u{1b}[?1049h")
        try require(!view.scrollbackReplay.isHolding, "Alternate-screen switch retained an old reading image")
        feed("\u{1b}[?1049l"); feed(rows(0..<1000)); view.scrollTo(row: 100); feed(clear)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{f700}", charactersIgnoringModifiers: "\u{f700}", isARepeat: false, keyCode: 126)!
        view.keyDown(with: key)
        try require(!view.scrollbackReplay.isHolding, "Keyboard input left the reading image covering live output")
        // The same clear still jumps in an ordinary terminal: only Codex opts in.
        view.usesApplicationScrolling = false; feed(rows(0..<1000)); view.scrollTo(row: 100); feed(clear)
        try require(!view.scrollbackReplay.isHolding && view.getTerminal().buffer.yDisp == 0, "Changed ordinary shell clear semantics")
        print("PASS: Codex CSI 3J replay: reading image, chunked/repeated clears, exact content anchor, queued wheel intent, bottom follow, bounded fallback, input/buffer cleanup and ordinary-shell isolation")
    }
}
