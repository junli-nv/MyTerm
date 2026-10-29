import AppKit
import MyTermCore

/// Exercise both directions beyond the former 520-point content cap, including
/// intermediate live-resize frames, without connecting to a remote server.
enum SFTPResizeCheck {
    static func run(window: NSWindow, terminal: NSView) throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let content = window.contentView,
              let split = descendants(content).compactMap({ $0 as? NSSplitView }).first(where: {
                  $0.isVertical && $0.arrangedSubviews.count == 2
                    && terminal.isDescendant(of: $0.arrangedSubviews[0])
                    && descendants($0.arrangedSubviews[1]).contains(where: { $0 is SFTPTableView })
              }) else { throw ConfigurationError.invalid("SFTP resize: missing inline split") }
        let original = split.arrangedSubviews[0].frame.width
        let dividerWidth = split.dividerThickness

        defer { split.setPosition(original, ofDividerAt: 0); content.layoutSubtreeIfNeeded() }
        func checkBackground() throws {
            content.layoutSubtreeIfNeeded()
            split.displayIfNeeded()
            let pane = split.arrangedSubviews[1]
            let rect = pane.convert(pane.bounds, to: content)
            guard rect.width >= 300, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                throw ConfigurationError.invalid("SFTP resize: cannot capture panel")
            }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let sx = CGFloat(bitmap.pixelsWide) / content.bounds.width
            let sy = CGFloat(bitmap.pixelsHigh) / content.bounds.height
            let top = content.isFlipped ? rect.minY : content.bounds.height - rect.maxY
            // Include the terminal gutter and the divider: checking the panel alone
            // missed holes punched by an oversized, clipped terminal document.
            let left = split.arrangedSubviews[0]
            let leftRect = left.convert(left.bounds, to: content)
            guard abs(rect.minX - leftRect.maxX - dividerWidth) < 0.01,
                  abs(dividerWidth - 1) < 0.01 else {
                throw ConfigurationError.invalid("SFTP resize: divider must remain exactly 1pt")
            }
            for x in stride(from: leftRect.maxX - 8, to: rect.minX + 2, by: 1 / sx) {
                for y in [top + 20, top + rect.height / 2, top + rect.height - 20] {
                    let alpha = bitmap.colorAt(x: Int(x * sx), y: Int(y * sy))?.alphaComponent ?? 0
                    guard alpha > 0.98 else {
                        throw ConfigurationError.invalid("SFTP resize: transparent boundary at x=\(x - leftRect.maxX), width=\(rect.width), alpha=\(alpha)")
                    }
                }
            }
            // Test panel margins outside the native table, where a capped/centered
            // SwiftUI background used to expose the clear main window.
            for x in [rect.minX + 2, rect.maxX - 2] {
                for y in [top + 1, top + rect.height / 2, top + rect.height - 2] {
                    let alpha = bitmap.colorAt(x: Int(x * sx), y: Int(y * sy))?.alphaComponent ?? 0
                    guard alpha > 0.98 else {
                        throw ConfigurationError.invalid("SFTP resize: transparent panel margin at width \(rect.width)")
                    }
                }
            }
        }
        do {
            split.viewWillStartLiveResize()
            defer { split.viewDidEndLiveResize() }
            for width: CGFloat in [360, 480, 560, 680, 560, 420, 340] {
                split.setPosition(split.bounds.width - split.dividerThickness - width, ofDividerAt: 0)
                content.layoutSubtreeIfNeeded()
                try checkBackground() // Before the delayed terminal grid resize.
                RunLoop.main.run(until: Date().addingTimeInterval(0.16))
                guard abs(split.arrangedSubviews[1].frame.width - width) < 2 else {
                    throw ConfigurationError.invalid("SFTP resize: requested width was constrained")
                }
                try checkBackground()
            }
        }
        try checkBackground()
        print("PASS: SFTP boundary: fixed 1pt divider, clipped terminal gutter, expand/shrink before and after delayed sizing")
    }
}
