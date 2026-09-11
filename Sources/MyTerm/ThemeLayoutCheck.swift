#if DEBUG
import AppKit
import SwiftUI

/// Render at the space available inside the fixed-size Settings tab view.
enum ThemeLayoutCheck {
    static func run() {
        guard let index = CommandLine.arguments.firstIndex(of: "--theme-snapshots"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { language.selection = original }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for selection in [InterfaceLanguage.chinese, .english] {
                language.selection = selection
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 550), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let view = NSHostingView(rootView: ThemeSettingsView().environment(\.locale, language.locale))
                window.contentView = view; window.orderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("theme-\(selection.rawValue).png"))
                }
                window.orderOut(nil); window.close()
            }
            print("PASS: rendered Chinese and English font settings at the available tab dimensions")
        } catch { fputs("FAIL: theme snapshot: \(error)\n", stderr); exit(1) }
    }
}
#endif
