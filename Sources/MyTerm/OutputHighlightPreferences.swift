import AppKit
import SwiftUI
import MyTermCore

final class OutputHighlightPreferences: ObservableObject {
    static let shared = OutputHighlightPreferences()
    private let defaults: UserDefaults
    private let persists: Bool
    @Published var configuration: OutputHighlightConfiguration {
        didSet {
            guard (try? configuration.validate()) != nil else { return }
            if persists, let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "terminal.outputHighlight") }
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        persists = !ProcessInfo.processInfo.arguments.contains("--smoke-test")
        if let data = defaults.data(forKey: "terminal.outputHighlight"), let saved = try? JSONDecoder().decode(OutputHighlightConfiguration.self, from: data), (try? saved.validate()) != nil {
            configuration = saved
        } else { configuration = OutputHighlightConfiguration() }
    }
}

struct OutputHighlightSettingsView: View {
    @ObservedObject var language = LanguagePreferences.shared
    @ObservedObject var preferences = OutputHighlightPreferences.shared
    private func color(_ id: UUID) -> Binding<Color> {
        Binding(get: {
            let c = preferences.configuration.rules.first { $0.id == id }?.color ?? HighlightColor(239, 83, 80)
            return Color(nsColor: NSColor(srgbRed: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255, alpha: 1))
        }, set: { value in
            guard let index = preferences.configuration.rules.firstIndex(where: { $0.id == id }), let c = NSColor(value).usingColorSpace(.sRGB) else { return }
            preferences.configuration.rules[index].color = HighlightColor(UInt8(min(255, max(0, (c.redComponent * 255).rounded()))), UInt8(min(255, max(0, (c.greenComponent * 255).rounded()))), UInt8(min(255, max(0, (c.blueComponent * 255).rounded()))))
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用输出关键词着色", isOn: $preferences.configuration.enabled)
                Toggle("同时应用于本地终端", isOn: $preferences.configuration.includeLocal)
                Toggle("同时应用于 tmux / vim 等全屏程序", isOn: $preferences.configuration.includeAlternate)
                Toggle("保留服务器已有的文字颜色", isOn: $preferences.configuration.preserveANSI)
                Text("仅改变显示颜色，复制、历史导出和文件传输保留原文。修改立即生效。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("用逗号分隔关键词；按列表顺序优先匹配。仅匹配文字，不使用正则表达式。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($preferences.configuration.rules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("启用规则", isOn: $rule.enabled)
                            Spacer()
                            ColorPicker("文字颜色", selection: color(rule.id), supportsOpacity: false)
                            Button("上移") { move(rule.id) }.disabled(preferences.configuration.rules.first?.id == rule.id)
                            Button("删除") { preferences.configuration.rules.removeAll { $0.id == rule.id } }
                        }
                        TextField("关键词（例如 error, failed）", text: $rule.keywords).textFieldStyle(.roundedBorder)
                        HStack {
                            Toggle("完整词匹配", isOn: $rule.wholeWords)
                            Toggle("区分大小写", isOn: $rule.caseSensitive)
                        }.font(.caption)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    Button("添加规则") { preferences.configuration.rules.append(.init(keywords: "", color: .init(239, 83, 80))) }
                        .disabled(preferences.configuration.rules.count >= 32)
                    Button("恢复默认着色规则") { preferences.configuration.rules = OutputHighlightConfiguration().rules }
                }
                if let error = validationError { Text(L10n.text(error)).foregroundStyle(.red).font(.caption) }
            }.padding(20)
        }
    }
    private var validationError: String? {
        do { try preferences.configuration.validate(); return nil } catch { return error.localizedDescription }
    }
    private func move(_ id: UUID) {
        guard let index = preferences.configuration.rules.firstIndex(where: { $0.id == id }), index > 0 else { return }
        preferences.configuration.rules.swapAt(index, index - 1)
    }
}
