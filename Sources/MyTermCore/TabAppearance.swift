import Foundation

public enum TabColor: String, Codable, CaseIterable {
    case automatic, red, orange, yellow, green, blue, purple, gray
    public var title: String {
        switch self {
        case .automatic: return "默认"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .gray: return "灰色"
        }
    }
}

/// Presentation metadata only: never used to choose an SSH target or credentials.
public struct TabAppearance: Codable, Equatable {
    public var color: TabColor = .automatic
    public var environment: String = ""
    public init(color: TabColor = .automatic, environment: String = "") {
        self.color = color; self.environment = environment
    }
    public func validated() throws -> Self {
        var result = self
        result.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.environment.count <= 24,
              !result.environment.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConfigurationError.invalid("环境标识最多 24 个字符，不能包含控制字符。")
        }
        return result
    }
}
