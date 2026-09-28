import SwiftUI

/// MyTerm palettes inspired by the user's dark-terminal and soft daylight references.
/// Explicit ANSI values keep presets complete and independent of the previous theme.
struct ThemePreset {
    let name: String
    let light: Bool
    let background: String
    let foreground: String
    let cursor: String
    let selection: String
    let ansi: [String]

    func apply(to theme: inout TerminalTheme) {
        theme.appearance = light ? "light" : "dark"
        theme.background = ThemeColor(hex: background)!
        theme.foreground = ThemeColor(hex: foreground)!
        theme.cursor = ThemeColor(hex: cursor)!
        theme.selection = ThemeColor(hex: selection)!
        theme.ansi = ansi.map { ThemeColor(hex: $0)! }
    }
    static let additional: [ThemePreset] = [
        ThemePreset(name: "夜空", light: false, background: "1C2030", foreground: "D5DDF1", cursor: "87B4EF", selection: "384966",
                    ansi: ["32394F", "EE8697", "A7CC83", "E6C180", "89ADF3", "C4A0EC", "83C9CE", "D5DDF1", "7A86A4", "FFA8B5", "C1E5A0", "F5D89C", "ACC8FF", "DEBCFF", "A6E3E5", "F1F4FC"]),
        ThemePreset(name: "北境", light: false, background: "292F3A", foreground: "DFE6EF", cursor: "99C9D4", selection: "455569",
                    ansi: ["3B4453", "D5878F", "AAC79A", "E5C48D", "91ACD4", "C6A3C4", "8DC4CB", "D8E0EC", "8490A5", "EBA4AC", "C0DDB1", "F5DAA8", "AEC6EA", "DEC0DC", "ACDEE2", "F2F5FA"]),
        ThemePreset(name: "柔雾", light: true, background: "E9EBF0", foreground: "343F59", cursor: "345D98", selection: "CBD6EB",
                    ansi: ["30384D", "A83F59", "3D693D", "79581F", "365D9E", "774A94", "256974", "BAC0CE", "626D83", "B54361", "39703C", "805919", "315DA8", "82509D", "216E7B", "DADEE8"]),
        ThemePreset(name: "暖奶油", light: true, background: "FBF5E8", foreground: "493E34", cursor: "8B5B2E", selection: "E6D6B7",
                    ansi: ["493E34", "A83E3E", "4F6835", "805B1E", "3C6390", "805080", "356D6A", "C9BEAA", "796C5C", "B44842", "4D7037", "87591A", "396797", "8B528B", "317773", "EBE1CE"])
    ]
    static var names: [String] { ["深色", "浅色", "Solarized", "午夜蓝", "柔和纸白"] + additional.map(\.name) }
}

struct ThemePresetPicker: View {
    @ObservedObject var preferences: ThemePreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预设").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(ThemePreset.names, id: \.self) { name in
                    let preview = ThemePreferences.presetTheme(name)
                    Button { preferences.preset(name) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text(name)).font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 4) {
                                ForEach(1..<7) { index in
                                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: preview.ansi[index].native)).frame(height: 7)
                                }
                            }
                            Text("Aa 0123  ~ / ssh").font(.system(size: 12, design: .monospaced))
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Color(nsColor: preview.foreground.native))
                            .background(Color(nsColor: preview.background.native), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(Text(L10n.text(name)))
                }
            }
        }
    }
}
