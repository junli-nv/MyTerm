import AppKit
import QuartzCore

/// CSI 3J genuinely deletes history. Keep only the visible reading image and a
/// small text anchor in memory while Codex replays it; never block PTY parsing,
/// retain the old full buffer, persist the image/text, or ignore the clear.
final class CodexScrollbackReplay {
    private struct Anchor {
        let row: Int, maximum: Int, columns: Int, rows: Int
        let signature: [String]
        var desired: Int
        var scanned = 0
        var bestMatch: Int?
    }
    private weak var view: MouseTerminalView?
    private var anchor: Anchor?
    private var image: NSImage?
    private var generation: UUID?
    private var expiryTimer: Timer?
    var isHolding: Bool { anchor != nil }
    var hasReadingImage: Bool { image != nil }
    init(view: MouseTerminalView) { self.view = view }

    func begin() {
        guard let view, Thread.isMainThread, view.usesApplicationScrolling,
              !view.getTerminal().isDisplayBufferAlternate else { return }
        if anchor != nil {
            anchor?.scanned = 0; anchor?.bestMatch = nil
            return
        }
        guard view.canScroll, view.scrollPosition < 1 else { return }
        let terminal = view.getTerminal(), row = terminal.buffer.yDisp
        let signature = (0..<min(5, terminal.rows)).compactMap {
            terminal.getScrollInvariantLine(row: row + $0)?.translateToString(trimRight: true)
        }
        // Capture before setting image so cacheDisplay cannot capture itself.
        if view.window != nil, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            // The layer already paints the theme background under draw(_:).
            // Cache only its foreground content or alpha would be applied twice.
            let background = view.layer?.backgroundColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.cacheDisplay(in: view.bounds, to: bitmap)
            view.layer?.backgroundColor = background
            CATransaction.commit()
            let snapshot = NSImage(size: view.bounds.size); snapshot.addRepresentation(bitmap)
            image = snapshot
        }
        anchor = Anchor(row: row, maximum: terminal.scrollbackRowCount, columns: terminal.cols, rows: terminal.rows,
            signature: signature.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } ? [] : signature, desired: row)
        view.selection.selectNone()
        let token = UUID(); generation = token
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard self?.generation == token else { return }
            self?.expire()
        }
        expiryTimer = timer
        // Common modes keep the bound effective during AppKit event tracking.
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Replace this surface's pixels instead of layering translucent images
    /// over live text; preserve theme alpha without letting replay bleed through.
    func draw(in bounds: NSRect) -> Bool {
        guard isHolding, let image else { return false }
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        return true
    }

    func receivedOutput() {
        guard let view, var saved = anchor else { return }
        let terminal = view.getTerminal(), maximum = terminal.scrollbackRowCount
        guard !terminal.isDisplayBufferAlternate, terminal.cols == saved.columns, terminal.rows == saved.rows else { cancel(); return }
        if !saved.signature.isEmpty {
            let start = max(0, saved.scanned - saved.signature.count + 1)
            if start <= maximum {
                for row in start...maximum {
                    let matches = saved.signature.indices.allSatisfy {
                        terminal.getScrollInvariantLine(row: row + $0)?.translateToString(trimRight: true) == saved.signature[$0]
                    }
                    if matches, saved.bestMatch == nil || abs(row - saved.row) < abs(saved.bestMatch! - saved.row) { saved.bestMatch = row }
                }
            }
            saved.scanned = maximum + 1
        }
        anchor = saved
        if let match = saved.bestMatch, abs(match - saved.row) <= saved.rows || maximum >= saved.maximum {
            finish(row: match + saved.desired - saved.row)
        } else if saved.signature.isEmpty, maximum >= saved.desired {
            finish(row: saved.desired)
        }
    }

    /// Retain the native wheel's row delta, including momentum, during replay.
    @discardableResult func scroll(lines: Int) -> Bool {
        guard var saved = anchor else { return false }
        saved.desired = max(0, min(saved.maximum, saved.desired - lines))
        anchor = saved
        if saved.desired == saved.maximum { finish(row: view?.getTerminal().scrollbackRowCount ?? 0) }
        else { receivedOutput() }
        return true
    }
    func expire() {
        guard let saved = anchor else { return }
        // A real clear or rewritten content may never reproduce the anchor.
        // Bound the hold and use the nearest surviving row rather than freezing.
        finish(row: (saved.bestMatch ?? saved.row) + saved.desired - saved.row)
    }
    func cancel() {
        let hadImage = image != nil
        expiryTimer?.invalidate(); expiryTimer = nil
        anchor = nil; generation = nil; image = nil
        if hadImage { view?.needsDisplay = true }
    }
    private func finish(row: Int) {
        guard let view else { cancel(); return }
        cancel()
        view.scrollTo(row: row)
        view.needsDisplay = true
    }
}
