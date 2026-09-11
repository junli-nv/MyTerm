import AppKit
import SwiftTerm
import MyTermCore

extension ThemeColor {
    var valid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "", options: .anchored)
        guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isHexDigit }), let number = UInt32(value, radix: 16) else { return nil }
        self.init(Double((number >> 16) & 255) / 255, Double((number >> 8) & 255) / 255, Double(number & 255) / 255)
    }
    var terminalColor: SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16((red * 65535).rounded()), green: UInt16((green * 65535).rounded()), blue: UInt16((blue * 65535).rounded()))
    }
}

extension TerminalTheme {
    static var defaultANSI: [ThemeColor] {
        SwiftTerm.Color.terminalAppColors.map { ThemeColor(Double($0.red) / 65535, Double($0.green) / 65535, Double($0.blue) / 65535) }
    }
    static let colorFields: [(String, WritableKeyPath<TerminalTheme, ThemeColor>)] = [
        ("Foreground Color", \.foreground), ("Background Color", \.background),
        ("Cursor Color", \.cursor), ("Cursor Text Color", \.cursorText),
        ("Selection Color", \.selection), ("Selected Text Color", \.selectionText)
    ]
    func validateColors() throws {
        guard backgroundOpacity.isFinite, (0...1).contains(backgroundOpacity), ansi.count == 16, ansi.allSatisfy(\.valid), Self.colorFields.allSatisfy({ self[keyPath: $0.1].valid }) else {
            throw ConfigurationError.invalid("颜色值必须在 0–1 之间，ANSI 调色板必须包含 16 色。")
        }
    }
    /// Missing keys retain the current color; font and interface appearance never come from a color file.
    func importingITerm(_ data: Data) throws -> TerminalTheme {
        guard data.count <= 1_048_576,
              let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ConfigurationError.invalid("无法读取配色文件，请选择有效的 .itermcolors 文件。")
        }
        var result = self, count = 0
        func read(_ key: String) throws -> ThemeColor? {
            guard let raw = dictionary[key] else { return nil }
            guard let entry = raw as? [String: Any], let red = entry["Red Component"] as? Double,
                  let green = entry["Green Component"] as? Double, let blue = entry["Blue Component"] as? Double else {
                throw ConfigurationError.invalid("配色文件包含无效的 RGB 颜色。")
            }
            let value = ThemeColor(red, green, blue)
            guard value.valid else { throw ConfigurationError.invalid("配色文件包含无效的 RGB 颜色。") }
            let space = entry["Color Space"] as? String ?? "Calibrated"
            let native: NSColor
            switch space {
            case "sRGB": native = value.native
            case "Calibrated": native = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
            case "P3": native = NSColor(displayP3Red: red, green: green, blue: blue, alpha: 1)
            default: throw ConfigurationError.invalid("配色文件包含不支持的颜色空间。")
            }
            count += 1
            let converted = ThemeColor(native)
            return ThemeColor(min(1, max(0, converted.red)), min(1, max(0, converted.green)), min(1, max(0, converted.blue)))
        }
        for (name, key) in Self.colorFields { if let color = try read(name) { result[keyPath: key] = color } }
        for index in 0..<16 { if let color = try read("Ansi \(index) Color") { result.ansi[index] = color } }
        guard count > 0 else { throw ConfigurationError.invalid("文件中没有可用的终端配色。") }
        try result.validateColors()
        return result
    }
    func exportingITerm() throws -> Data {
        try validateColors()
        func entry(_ color: ThemeColor) -> [String: Any] {
            ["Red Component": color.red, "Green Component": color.green, "Blue Component": color.blue, "Alpha Component": 1.0, "Color Space": "sRGB"]
        }
        var result: [String: Any] = [:]
        for (name, key) in Self.colorFields { result[name] = entry(self[keyPath: key]) }
        for index in 0..<16 { result["Ansi \(index) Color"] = entry(ansi[index]) }
        return try PropertyListSerialization.data(fromPropertyList: result, format: .xml, options: 0)
    }
}
