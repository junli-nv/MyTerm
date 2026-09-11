import AppKit
import SwiftUI

struct ThemeColor: Codable, Equatable {
    var red: Double, green: Double, blue: Double
    init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    init(_ color: NSColor) {
        let value = color.usingColorSpace(.sRGB) ?? .white
        self.init(min(1, max(0, value.redComponent)), min(1, max(0, value.greenComponent)), min(1, max(0, value.blueComponent)))
    }
    var native: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}
struct TerminalTheme: Codable, Equatable {
    var fontName = "Menlo-Regular"
    var fontSize = 14.0
    var foreground = ThemeColor(0.84, 0.87, 0.91)
    var background = ThemeColor(0.055, 0.067, 0.09)
    var cursor = ThemeColor(0.4, 0.9, 0.75)
    var selection = ThemeColor(0.13, 0.35, 0.43)
    var appearance = "dark"
    var cursorText = ThemeColor(0.055, 0.067, 0.09)
    var selectionText = ThemeColor(0, 0, 0)
    var ansi = TerminalTheme.defaultANSI
    var brightBold = true
    var backgroundOpacity = 1.0
    init() {}
    enum CodingKeys: String, CodingKey {
        case fontName, fontSize, foreground, background, cursor, selection, appearance, cursorText, selectionText, ansi, brightBold, backgroundOpacity
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fontName
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        foreground = try c.decodeIfPresent(ThemeColor.self, forKey: .foreground) ?? foreground
        background = try c.decodeIfPresent(ThemeColor.self, forKey: .background) ?? background
        cursor = try c.decodeIfPresent(ThemeColor.self, forKey: .cursor) ?? cursor
        selection = try c.decodeIfPresent(ThemeColor.self, forKey: .selection) ?? selection
        cursorText = try c.decodeIfPresent(ThemeColor.self, forKey: .cursorText) ?? background
        selectionText = try c.decodeIfPresent(ThemeColor.self, forKey: .selectionText) ?? selectionText
        ansi = try c.decodeIfPresent([ThemeColor].self, forKey: .ansi) ?? ansi
        brightBold = try c.decodeIfPresent(Bool.self, forKey: .brightBold) ?? brightBold
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1
        try validateColors()
    }
}
final class ThemePreferences: ObservableObject {
    static let shared = ThemePreferences()
    private let defaults: UserDefaults
    @Published var theme: TerminalTheme { didSet { if let data = try? JSONEncoder().encode(theme) { defaults.set(data, forKey: "terminal.theme") } } }
    @Published private(set) var fonts: [String] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = defaults.data(forKey: "terminal.theme").flatMap { try? JSONDecoder().decode(TerminalTheme.self, from: $0) } ?? TerminalTheme()
        saved.fontSize = saved.fontSize.isFinite ? min(36, max(9, saved.fontSize)) : 14
        if NSFont(name: saved.fontName, size: saved.fontSize) == nil { saved.fontName = "Menlo-Regular" }
        theme = saved
        refreshFonts()
    }
    func refreshFonts() {
        fonts = Array(Set(NSFontManager.shared.availableFonts + [theme.fontName, "Menlo-Regular", "Monaco"]))
            .filter { NSFont(name: $0, size: 14) != nil }.sorted()
    }
    func useFont(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let font = NSFont(name: name, size: theme.fontSize) else { return false }
        theme.fontName = font.fontName
        refreshFonts()
        return true
    }
    var scheme: ColorScheme? { theme.appearance == "system" ? nil : theme.appearance == "light" ? .light : .dark }
    func apply(to terminal: MouseTerminalView) {
        let font = NSFont(name: theme.fontName, size: theme.fontSize) ?? .monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        if terminal.font != font { terminal.font = font }
        terminal.nativeForegroundColor = theme.foreground.native
        terminal.nativeBackgroundColor = theme.background.native
        terminal.backgroundOpacity = theme.backgroundOpacity
        terminal.caretColor = theme.cursor.native
        terminal.caretTextColor = theme.cursorText.native
        terminal.selectedTextBackgroundColor = theme.selection.native
        terminal.selectedTextForegroundColor = theme.selectionText.native
        terminal.useBrightColors = theme.brightBold
        if terminal.appliedANSI != theme.ansi {
            terminal.installColors(theme.ansi.map(\.terminalColor))
            terminal.appliedANSI = theme.ansi
        }
    }
    func preset(_ name: String) {
        var value = TerminalTheme()
        value.fontName = theme.fontName; value.fontSize = theme.fontSize
        value.backgroundOpacity = theme.backgroundOpacity
        if name == "浅色" {
            value.appearance = "light"; value.background = ThemeColor(0.97, 0.97, 0.96)
            value.foreground = ThemeColor(0.12, 0.14, 0.17); value.cursor = ThemeColor(0.1, 0.35, 0.65)
            value.selection = ThemeColor(0.7, 0.83, 0.95)
        } else if name == "Solarized" {
            value.background = ThemeColor(0, 0.17, 0.21); value.foreground = ThemeColor(0.58, 0.63, 0.63)
            value.cursor = ThemeColor(0.71, 0.54, 0); value.selection = ThemeColor(0.03, 0.25, 0.29)
        }
        if name == "午夜蓝" {
            value.background = ThemeColor(hex: "#101827")!; value.foreground = ThemeColor(hex: "#D6E4F0")!
            value.ansi = ["182334", "F27883", "86D6A0", "F4D58A", "82B5F5", "CAA4EA", "7DD8DC", "CFDCE8", "62758B", "FFA0A8", "A9EDBB", "FFE4A3", "A6CCFF", "E0C2FA", "A1EBEE", "F1F7FC"].map { ThemeColor(hex: $0)! }
        } else if name == "柔和纸白" {
            value.appearance = "light"; value.background = ThemeColor(hex: "#FAF7F0")!; value.foreground = ThemeColor(hex: "#343B43")!
            value.cursor = ThemeColor(hex: "#285C85")!; value.selection = ThemeColor(hex: "#CDDDE9")!
            value.ansi = ["343B43", "AC3343", "35734A", "886B17", "315EAC", "85469C", "227980", "CBD0D5", "626E79", "C44555", "408354", "98781B", "426EBB", "9957AF", "2E8C92", "EEECE5"].map { ThemeColor(hex: $0)! }
        } else if name == "Solarized" {
            value.ansi = ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5", "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"].map { ThemeColor(hex: $0)! }
        }
        value.cursorText = value.background
        value.selectionText = value.foreground
        theme = value
    }
}

private final class FontSelectionDraft: ObservableObject {
    @Published var fontSearch = ""
    @Published var customFont = ""
    @Published var fontError: String?
    @Published var onlyMonospaced = false
}

struct ThemeSettingsView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var preferences = ThemePreferences.shared
    @StateObject private var draft = FontSelectionDraft()
    private var visibleFonts: [String] {
        preferences.fonts.filter { name in
            name == preferences.theme.fontName ||
            ((!draft.onlyMonospaced || NSFont(name: name, size: 14)?.isFixedPitch == true) &&
             (draft.fontSearch.isEmpty || name.localizedCaseInsensitiveContains(draft.fontSearch)))
        }
    }
    private func applyCustomFont() {
        draft.fontError = preferences.useFont(named: draft.customFont) ? nil : "未找到此字体，请先通过 macOS 字体册安装，再点击刷新。"
    }
    var body: some View {
        GeometryReader { geometry in
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 16) {
            ThemeSettingRow(title: "预设") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 8)], spacing: 8) {
                ForEach(["深色", "浅色", "Solarized", "午夜蓝", "柔和纸白"], id: \.self) { name in
                    Button { preferences.preset(name) } label: {
                        Text(L10n.text(name)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                    }
                }
            }
            }
            ThemeSettingRow(title: "界面外观") {
                Picker("界面外观", selection: $preferences.theme.appearance) {
                    Text("跟随系统").tag("system"); Text("深色").tag("dark"); Text("浅色").tag("light")
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            ThemeSettingRow(title: "终端字体") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("终端字体", selection: $preferences.theme.fontName) {
                    ForEach(visibleFonts, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                Text(preferences.theme.fontName).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            ThemeSettingRow(title: "搜索已安装字体") {
                HStack(spacing: 12) {
                    TextField("", text: $draft.fontSearch).labelsHidden()
                        .accessibilityLabel(Text("搜索已安装字体"))
                        .textFieldStyle(.roundedBorder).frame(minWidth: 80, maxWidth: .infinity)
                    Toggle("仅等宽", isOn: $draft.onlyMonospaced).fixedSize()
                    Button("刷新", action: preferences.refreshFonts).fixedSize()
                }
            }
            ThemeSettingRow(title: "自定义字体名称（如 Menlo-Regular）") {
                HStack(spacing: 12) {
                    TextField("", text: $draft.customFont, prompt: Text("Menlo-Regular")).labelsHidden()
                        .accessibilityLabel(Text("自定义字体名称（如 Menlo-Regular）"))
                        .textFieldStyle(.roundedBorder).frame(minWidth: 80, maxWidth: .infinity).onSubmit(applyCustomFont)
                    Button("应用字体", action: applyCustomFont).fixedSize()
                }
            }
            if let fontError = draft.fontError { Text(L10n.text(fontError)).font(.caption).foregroundStyle(.red) }
            Text("默认列出全部已安装字体。终端表格与 tmux 推荐使用等宽字体，如 Menlo、Monaco、Courier；安装其他字体后点击刷新即可选择。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ThemeSettingRow(title: "字号") {
                Stepper("\(preferences.theme.fontSize.formatted()) pt", value: $preferences.theme.fontSize, in: 9...36, step: 0.5)
                    .fixedSize()
            }
            Text("Ctrl + 双指上滑放大，下滑缩小；每步 0.5 pt。").font(.caption).foregroundStyle(.secondary)
            ThemeColorControls(preferences: preferences)
        }.frame(width: max(0, geometry.size.width - 40), alignment: .leading).padding(20)
        }
        }.onAppear { preferences.refreshFonts() }
    }
}
