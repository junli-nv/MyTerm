import AppKit
import SwiftUI

enum InterfaceLanguage: String, CaseIterable { case system, chinese, english }
final class LanguagePreferences: ObservableObject {
    static let shared = LanguagePreferences()
    static let didChange = Notification.Name("MyTerm.interfaceLanguageChanged")
    private let persists: Bool
    var identifier: String {
        switch selection {
        case .chinese: return "zh-Hans"
        case .english: return "en"
        case .system:
            let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
            return languages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
    var locale: Locale { Locale(identifier: identifier) }
    @Published var selection: InterfaceLanguage {
        didSet {
            if persists {
                UserDefaults.standard.set(selection.rawValue, forKey: "interface.language")
                if selection == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                else { UserDefaults.standard.set([selection == .chinese ? "zh-Hans" : "en"], forKey: "AppleLanguages") }
            }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    init() {
        persists = !ProcessInfo.processInfo.arguments.contains("--smoke-test")
        selection = InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interface.language") ?? "system") ?? .system
    }
}
enum L10n {
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["en", "zh-Hans"].compactMap { language in
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language, bundle)
    })
    static func text(_ value: String) -> String {
        let identifier = LanguagePreferences.shared.identifier
        let translated = (bundles[identifier] ?? Bundle.main).localizedString(forKey: value, value: value, table: nil)
        guard translated == value, identifier == "en" else { return translated }
        for (prefix, english) in [("导入失败：", "Import failed: "), ("导出失败：", "Export failed: "),
                                  ("无法读取保存的会话：", "Could not read saved sessions: "),
                                  ("Zmodem 启动失败：", "Zmodem failed to start: ")] where value.hasPrefix(prefix) {
            return english + text(String(value.dropFirst(prefix.count)))
        }
        let retry = " · 按 R 重新连接"
        if value.hasSuffix(retry) { return text(String(value.dropLast(retry.count))) + " · Press R to reconnect" }
        if value.range(of: #"^\d+ 个项目$"#, options: .regularExpression) != nil { return value.replacingOccurrences(of: " 个项目", with: " items") }
        if value.hasPrefix("Zmodem 传输未完成（") { return value.replacingOccurrences(of: "Zmodem 传输未完成（", with: "Zmodem transfer incomplete (").replacingOccurrences(of: "）", with: ")") }
        return value
    }
}
struct LanguageSettingsView: View {
    @ObservedObject private var preferences = LanguagePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("界面语言").font(.title2.bold())
            Picker("语言", selection: $preferences.selection) {
                Text("跟随系统").tag(InterfaceLanguage.system)
                Text("中文（简体）").tag(InterfaceLanguage.chinese)
                Text("English").tag(InterfaceLanguage.english)
            }
            Text("语言切换立即生效，并自动保存。当前连接不会被中断。")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }
}
