import AppKit
import SwiftUI
import MyTermCore

enum ThemeColorCheck {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Theme colors: " + message) }
        }
        let defaults = UserDefaults(suiteName: "MyTerm.ThemeColorCheck.\(UUID())")!
        defer { defaults.removeObject(forKey: "terminal.theme") }
        let preferences = ThemePreferences(defaults: defaults)
        preferences.theme.fontSize = 5
        let smallFont = ThemePreferences(defaults: defaults)
        let smallTerminal = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        smallFont.apply(to: smallTerminal)
        try require(smallFont.theme.fontSize == 5 && smallTerminal.font.pointSize == 5, "5pt font did not persist/apply")
        preferences.theme.fontSize = 2
        try require(ThemePreferences(defaults: defaults).theme.fontSize == 5, "Font lower bound was not clamped")
        let original = TerminalTheme()
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        for key in ["cursorText", "selectionText", "ansi", "brightBold", "backgroundOpacity"] { old.removeValue(forKey: key) }
        old["fontSize"] = 19.0
        let migrated = try JSONDecoder().decode(TerminalTheme.self, from: JSONSerialization.data(withJSONObject: old))
        try require(migrated.fontSize == 19 && migrated.ansi == TerminalTheme.defaultANSI && migrated.backgroundOpacity == 1, "Legacy theme migration")
        try require(ThemeColor(hex: "#aBcD09")?.hex == "#ABCD09" && ThemeColor(hex: "#12ZZ00") == nil, "HEX validation")
        preferences.theme = migrated
        preferences.preset("午夜蓝")
        preferences.theme.backgroundOpacity = 0.45
        preferences.theme.cursorText = ThemeColor(hex: "#102030")!
        preferences.theme.selectionText = ThemeColor(hex: "#FAEEDD")!
        let exported = try preferences.theme.exportingITerm()
        let roundtrip = try preferences.theme.importingITerm(exported)
        try require(roundtrip == preferences.theme, "iTerm color roundtrip")
        let persisted = ThemePreferences(defaults: defaults)
        try require(persisted.theme == preferences.theme, "Persistence")
        let partial = try PropertyListSerialization.data(fromPropertyList: ["Background Color": ["Red Component": 0.2, "Green Component": 0.3, "Blue Component": 0.4, "Color Space": "sRGB"]], format: .xml, options: 0)
        let imported = try preferences.theme.importingITerm(partial)
        try require(imported.fontSize == 19 && imported.ansi == preferences.theme.ansi && imported.backgroundOpacity == 0.45, "Partial import preserves other settings")
        for object: [String: Any] in [[:], ["Ansi 0 Color": ["Red Component": 3, "Green Component": 0, "Blue Component": 0]]] {
            let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            var rejected = false
            do { _ = try original.importingITerm(data) } catch { rejected = true }
            try require(rejected, "Invalid import accepted")
        }
        let terminal = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 180))
        terminal.feed(text: "\u{1b}[31mred\u{1b}[0m 中文\r\n")
        preferences.apply(to: terminal)
        try require(terminal.appliedANSI == preferences.theme.ansi && abs(terminal.backgroundOpacity - 0.45) < 0.001, "Palette/opacity application")
        try require(terminal.caretTextColor == preferences.theme.cursorText.native && terminal.selectedTextForegroundColor == preferences.theme.selectionText.native, "Cursor/selection colors")
        preferences.theme.brightBold = false
        preferences.theme.ansi[1] = ThemeColor(hex: "#BA3210")!
        preferences.apply(to: terminal)
        try require(!terminal.useBrightColors && terminal.appliedANSI?[1] == preferences.theme.ansi[1], "Live changes")
        // Change only colors after font is established: no PTY size/text mutation.
        let after = terminal.getTerminal().getBufferAsData(), cols = terminal.getTerminal().cols
        preferences.theme.backgroundOpacity = 1; preferences.apply(to: terminal)
        try require(terminal.getTerminal().getBufferAsData() == after && terminal.getTerminal().cols == cols, "Colors modified terminal content/grid")
        if let index = CommandLine.arguments.firstIndex(of: "--color-snapshot"), CommandLine.arguments.indices.contains(index + 1) {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let view = NSHostingView(rootView: ThemeColorControls(preferences: preferences).padding(24).environment(\.locale, Locale(identifier: "zh-Hans")))
            window.contentView = view; window.orderFront(nil); view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            window.close()
        }
        print("PASS: theme colors: legacy migration, HEX, iTerm import/export, persistence, ANSI/cursor/selection, opacity and content/grid preservation")
    }
}
