import AppKit
import SwiftUI
import UniformTypeIdentifiers

private final class ColorEditDraft: ObservableObject {
    @Published var hex = ""
    @Published var invalid = false
}

private struct ThemeColorRow: View {
    let title: String
    @Binding var value: ThemeColor
    @StateObject private var draft = ColorEditDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
            ColorPicker(L10n.text(title), selection: Binding(get: { Color(nsColor: value.native) }, set: { value = ThemeColor(NSColor($0)) }), supportsOpacity: false)
                .labelsHidden().fixedSize()
            TextField("#RRGGBB", text: $draft.hex)
                .font(.system(.caption, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 82)
                .accessibilityLabel(Text(L10n.text(title) + " HEX"))
                .onSubmit {
                    if let parsed = ThemeColor(hex: draft.hex) { value = parsed; draft.hex = parsed.hex; draft.invalid = false }
                    else { draft.invalid = true }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(draft.invalid ? Color.red : .clear))
                .help(L10n.text("输入 #RRGGBB 后按回车应用。"))
            Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { draft.hex = value.hex }
        .onChange(of: value) { _, new in draft.hex = new.hex; draft.invalid = false }
    }
}

private final class ColorFileDraft: ObservableObject { @Published var error: String? }
struct ThemeColorControls: View {
    @ObservedObject var preferences: ThemePreferences
    @StateObject private var draft = ColorFileDraft()
    private let names = ["黑色", "红色", "绿色", "黄色", "蓝色", "洋红", "青色", "白色"]
    private func binding(_ key: WritableKeyPath<TerminalTheme, ThemeColor>) -> Binding<ThemeColor> {
        Binding(get: { preferences.theme[keyPath: key] }, set: { preferences.theme[keyPath: key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Text("基础颜色").font(.headline)
                Spacer()
                Button("导入配色…", action: importColors)
                Button("导出配色…", action: exportColors)
            }
            Text("输入 #RRGGBB 后按回车应用。").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ThemeColorRow(title: "文字颜色", value: binding(\.foreground))
                    ThemeColorRow(title: "背景颜色", value: binding(\.background))

                    ThemeColorRow(title: "光标颜色", value: binding(\.cursor))
                    ThemeColorRow(title: "光标文字", value: binding(\.cursorText))

                    ThemeColorRow(title: "选区背景", value: binding(\.selection))
                    ThemeColorRow(title: "选区文字", value: binding(\.selectionText))
            }
            Divider()
            Text("背景不透明度").fixedSize(horizontal: false, vertical: true)
            HStack {
                Slider(value: $preferences.theme.backgroundOpacity, in: 0...1, step: 0.01)
                Text("\(Int((preferences.theme.backgroundOpacity * 100).rounded()))%").monospacedDigit().frame(width: 44)
            }
            Text("100% 完全不透明，0% 完全透明；仅影响默认背景，文字和选区保持清晰。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("ANSI 调色板").font(.headline)
            HStack { Text("标准色").frame(maxWidth: .infinity); Text("明亮色").frame(maxWidth: .infinity) }.font(.caption).foregroundStyle(.secondary)
            ForEach(0..<8, id: \.self) { index in
                HStack(spacing: 24) {
                    ThemeColorRow(title: names[index], value: $preferences.theme.ansi[index])
                    ThemeColorRow(title: names[index], value: $preferences.theme.ansi[index + 8])
                }
            }
            Toggle(isOn: $preferences.theme.brightBold) {
                Text("粗体使用明亮 ANSI 颜色").fixedSize(horizontal: false, vertical: true)
            }
            Text("ANSI 调色板控制程序使用的标准 16 色；RGB 真彩色保持程序指定的颜色。关键词着色在“输出着色”中单独设置。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("实时终端预览").font(.headline)
            ThemeTerminalPreview(preferences: preferences).frame(height: 150).clipped()
            Text("颜色立即应用到所有终端。配色导入导出使用 .itermcolors，保留当前字体和字号。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = draft.error { Text(L10n.text(error)).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func importColors() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .propertyList]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let next = try preferences.theme.importingITerm(Data(contentsOf: url))
            preferences.theme = next; draft.error = nil
        } catch { draft.error = error.localizedDescription }
    }
    private func exportColors() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .propertyList]
        panel.nameFieldStringValue = "MyTerm.itermcolors"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try preferences.theme.exportingITerm().write(to: url, options: .atomic); draft.error = nil }
        catch { draft.error = error.localizedDescription }
    }
}

struct ThemeTerminalPreview: NSViewRepresentable {
    @ObservedObject var preferences: ThemePreferences
    func makeNSView(context: Context) -> MouseTerminalView {
        let terminal = MouseTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 150))
        terminal.identifier = NSUserInterfaceItemIdentifier("theme.terminalPreview")
        preferences.apply(to: terminal)
        terminal.feed(text: "user@server:~ $ echo MyTerm 你好\r\n")
        for bright in [false, true] {
            for index in 0..<8 { terminal.feed(text: "\u{1b}[\((bright ? 90 : 30) + index)m Aa \u{1b}[0m") }
            terminal.feed(text: "\r\n")
        }
        terminal.feed(text: "\u{1b}[1mBold ANSI\u{1b}[0m   \u{1b}[38;2;120;180;240mRGB true color\u{1b}[0m\r\n")
        return terminal
    }
    func updateNSView(_ nsView: MouseTerminalView, context: Context) { preferences.apply(to: nsView) }
}
