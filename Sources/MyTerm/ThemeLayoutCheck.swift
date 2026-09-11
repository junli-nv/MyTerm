import AppKit
import SwiftUI

/// Use the real tab's available space, rather than an unconstrained component canvas.
enum ThemeLayoutCheck {
    static func run() {
        let args = CommandLine.arguments
        let snapshotIndex = args.firstIndex(of: "--theme-snapshots")
        guard snapshotIndex != nil || args.contains("--window-controls-check") else { return }
        let directory: URL? = snapshotIndex.flatMap { index in
            args.indices.contains(index + 1) ? URL(fileURLWithPath: args[index + 1]) : nil
        }
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { language.selection = original }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        do {
            if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            for selection in [InterfaceLanguage.chinese, .english] {
                language.selection = selection
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 550), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let view = NSHostingView(rootView: ThemeSettingsView().environment(\.locale, language.locale))
                window.contentView = view; window.orderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                view.layoutSubtreeIfNeeded()
                guard let scroll = descendants(view).compactMap({ $0 as? NSScrollView }).first,
                      let document = scroll.documentView else { throw CocoaError(.validationMissingMandatoryProperty) }
                guard document.frame.width <= scroll.contentSize.width + 1 else { throw CocoaError(.validationNumberTooLarge) }
                let maximum = max(0, document.frame.height - scroll.contentSize.height)
                for (page, fraction) in [0.0, 0.45, 1.0].enumerated() {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                    if let directory, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("theme-\(selection.rawValue)-\(page).png"))
                    }
                }
                window.orderOut(nil); window.close()
            }
            print("PASS: theme layout: Chinese/English at 736x550, no horizontal overflow, vertical scrolling")
        } catch { fputs("FAIL: theme layout: \(error)\n", stderr); exit(1) }
    }
}
