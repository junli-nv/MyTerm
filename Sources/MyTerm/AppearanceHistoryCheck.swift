#if DEBUG
import AppKit
import MyTermCore

enum AppearanceHistoryCheck {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid(message) }
        }
        let suite = "MyTerm.ThemeCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ThemePreferences(defaults: defaults)
        try require(preferences.fonts.contains("Menlo-Regular"), "Font list must include Menlo")
        try require(preferences.fonts.contains("Monaco"), "Installed font dropdown must include Monaco")
        preferences.theme.fontName = "Monaco"
        try require(ThemePreferences(defaults: defaults).theme.fontName == "Monaco", "Font dropdown selection must persist")
        preferences.theme.fontName = "MyTerm-Nonexistent-\(UUID())"
        try require(ThemePreferences(defaults: defaults).theme.fontName == "Menlo-Regular", "Missing saved font must fall back safely")
        preferences.theme.fontName = "Monaco"
        try require(NSFontManager.shared.availableFonts.filter { NSFont(name: $0, size: 14) != nil }.allSatisfy(preferences.fonts.contains), "Font list must expose all installed fonts")
        preferences.preset("浅色"); preferences.theme.fontSize = 18
        preferences.theme.foreground = ThemeColor(0.2, 0.3, 0.4)
        let restored = ThemePreferences(defaults: defaults)
        try require(restored.theme == preferences.theme, "Theme persistence mismatch")
        print("PASS: installed-font dropdown, missing-font fallback and persisted selection")
        let session = TerminalSession(label: "历史测试", executable: "/bin/bash", arguments: [])
        restored.apply(to: session.terminal)
        try require(session.terminal.font.pointSize == 18, "Font size did not apply")
        try require(session.terminal.nativeForegroundColor.usingColorSpace(.sRGB) == restored.theme.foreground.native, "Foreground did not apply")
        session.terminal.feed(text: "普通历史\r\n\u{1b}[31m彩色文字\u{1b}[0m\r\n")
        session.terminal.feed(text: "\u{1b}[?1049h全屏画面")
        let record = session.historySnapshot()
        try require(record.text.contains("普通历史") && record.text.contains("彩色文字") && record.text.contains("全屏画面"), "History lost normal or alternate screen: \(record.text.debugDescription)")
        try require(!record.text.contains("\u{1b}"), "Export must not contain ANSI escapes")
        let root = URL(fileURLWithPath: "/tmp/myterm-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = HistoryRepository(directory: root)
        try repo.save(record)
        let restoredHistory = try HistoryRepository(directory: root).load(record.id)
        try require(restoredHistory == record, "History did not survive reload")
        let output = root.appendingPathComponent("导出.txt")
        try HistoryRepository.export(restoredHistory.text, to: output)
        let exported = try String(contentsOf: output, encoding: .utf8)
        try require(exported == record.text, "UTF-8 text export differs")
        try repo.delete(record.id)
        try require(try repo.ids().isEmpty, "History delete failed")
        print("PASS: theme persistence and application, normal/alternate history, UTF-8 export and deletion")
    }
}
#endif
