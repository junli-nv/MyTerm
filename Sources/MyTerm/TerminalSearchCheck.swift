import AppKit
import SwiftTerm
import MyTermCore

enum TerminalSearchCheck {
    private final class RecordingTerminal: MouseTerminalView {
        var sent: [UInt8] = []
        override func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
    }
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("History search: " + message) }
        }
        let view = RecordingTerminal(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        view.resize(cols: 40, rows: 12); view.changeScrollback(300)
        view.feed(text: "needle FIRST\r\n" + String(repeating: "padding\r\n", count: 40) + "needle SECOND\r\n")
        let bottom = view.getTerminal().buffer.yDisp
        view.showHistorySearch()
        guard let bar = view.historySearch else { throw ConfigurationError.invalid("Search bar missing") }
        try require(view.getTerminal().buffer.yDisp == bottom, "Opening search moved viewport")
        bar.field.stringValue = "needle"; bar.navigate(next: true)
        try require(view.selection.getSelectedText() == "needle", "First literal match not selected")
        let first = view.selection.start
        try require(view.getTerminal().buffer.yDisp < bottom, "Old output not revealed")
        bar.navigate(next: true)
        try require(view.selection.start.row > first.row, "Next match did not advance")
        bar.navigate(next: false)
        try require(view.selection.start.row == first.row, "Previous match did not return")
        let anchor = view.getTerminal().buffer.yDisp
        view.feed(text: "more output\r\n")
        try require(view.getTerminal().buffer.yDisp == anchor, "Output stole search scroll position")
        view.clearSearch(); bar.field.stringValue = "NEEDLE"; bar.navigate(next: true)
        try require(view.selection.getSelectedText() == "needle", "Case-insensitive matching failed")
        bar.options.selectItem(at: 1); bar.options.sendAction(bar.options.action!, to: bar.options.target)
        bar.navigate(next: true)
        try require(!view.selection.active, "Case-sensitive mismatch matched")
        bar.options.selectItem(at: 1); bar.options.sendAction(bar.options.action!, to: bar.options.target)
        view.feed(text: "\r\n" + String(repeating: "x", count: 35) + "跨行中文NeedleWrap\r\n")
        view.clearSearch(); bar.field.stringValue = "跨行中文NeedleWrap"; bar.navigate(next: true)
        try require(view.selection.getSelectedText() == "跨行中文NeedleWrap", "Unicode soft-wrap match failed")
        view.resize(cols: 25, rows: 12); view.clearSearch(); bar.navigate(next: true)
        try require(view.selection.getSelectedText() == "跨行中文NeedleWrap", "Search after reflow failed")
        bar.field.stringValue = "no-such-text"; bar.navigate(next: true)
        try require(!view.selection.active && bar.status.stringValue == L10n.text("未找到匹配"), "No-result feedback missing")
        bar.options.selectItem(at: 3); bar.options.sendAction(bar.options.action!, to: bar.options.target)
        bar.field.stringValue = "["; bar.navigate(next: true)
        try require(bar.status.stringValue == L10n.text("正则表达式无效"), "Invalid regex lacks feedback")
        bar.field.stringValue = "needle [A-Z]+"; bar.navigate(next: true)
        try require(view.selection.getSelectedText().hasPrefix("needle "), "Regex matching failed")
        bar.options.selectItem(at: 3); bar.options.sendAction(bar.options.action!, to: bar.options.target)
        view.feed(text: "\u{1b}[?1049hALT_ONLY"); view.clearSearch()
        bar.field.stringValue = "ALT_ONLY"; bar.navigate(next: true)
        try require(view.selection.getSelectedText() == "ALT_ONLY", "Alternate-screen search failed")
        bar.field.stringValue = "needle"; bar.navigate(next: true)
        try require(!view.selection.active, "Alternate search leaked hidden normal buffer")
        view.feed(text: "\u{1b}[?1049l")
        let language = LanguagePreferences.shared; let original = language.selection
        defer { language.selection = original }
        for locale in [InterfaceLanguage.english, .chinese] {
            language.selection = locale
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            view.frame.size.width = 240; view.layoutSubtreeIfNeeded(); bar.layoutSubtreeIfNeeded()
            try require(bar.field.placeholderString == L10n.text("搜索终端历史"), "Stale search language")
            for control in [bar.field, bar.previous, bar.next, bar.close, bar.options, bar.status] {
                try require(bar.bounds.contains(control.frame), "Search controls clipped in narrow pane")
            }
        }
        bar.dismissSearch()
        try require(bar.isHidden && window.firstResponder === view && !view.selection.active, "Closing search lost terminal focus")
        try require(view.sent.isEmpty, "Search sent input to terminal process")
        print("PASS: terminal history search navigation, Unicode wraps/reflow, output anchor, alternate buffer, locale, narrow panes and zero remote input")
    }
    static func shortcuts(window: NSWindow, workspace: Workspace) throws {
        window.makeKeyAndOrderFront(nil)
        guard let view = workspace.selected?.terminal, let edit = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: { $0.items.contains { $0.title == L10n.text("搜索终端历史…") } }),
              let index = edit.items.firstIndex(where: { $0.title == L10n.text("搜索终端历史…") }) else { throw ConfigurationError.invalid("Search menu missing") }
        let item = edit.items[index]
        guard item.keyEquivalent == "f", edit.items.contains(where: { $0.keyEquivalent == "g" && $0.keyEquivalentModifierMask == [.command, .shift] }) else { throw ConfigurationError.invalid("Search shortcuts missing") }
        edit.performActionForItem(at: index)
        guard view.historySearch?.isHidden == false else { throw ConfigurationError.invalid("Menu did not open active pane search") }
        view.historySearch?.dismissSearch()
    }
}
