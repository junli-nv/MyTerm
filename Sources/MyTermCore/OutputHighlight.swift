import Foundation

public struct HighlightColor: Codable, Equatable {
    public var red: UInt8, green: UInt8, blue: UInt8
    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) { self.red = red; self.green = green; self.blue = blue }
}
public struct OutputHighlightRule: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var keywords: String
    public var color: HighlightColor
    public var wholeWords = true
    public var caseSensitive = false
    public init(keywords: String, color: HighlightColor) { self.keywords = keywords; self.color = color }
    public var terms: [String] {
        keywords.components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
public struct OutputHighlightConfiguration: Codable, Equatable {
    public var enabled = true
    public var includeLocal = false
    public var includeAlternate = false
    public var preserveANSI = true
    public var rules: [OutputHighlightRule] = [
        .init(keywords: "error, fail, failed, failure, fatal, critical, denied", color: .init(239, 83, 80)),
        .init(keywords: "up, active, ok, success, successful, passed, running", color: .init(76, 175, 80)),
        .init(keywords: "warn, warning, pending, retry", color: .init(255, 183, 77))
    ]
    public init() {}
    public func validate() throws {
        guard rules.count <= 32, Set(rules.map(\.id)).count == rules.count else {
            throw ConfigurationError.invalid("着色规则最多 32 条，且不能包含重复标识。")
        }
        for rule in rules {
            guard rule.keywords.count <= 1024, rule.terms.count <= 32,
                  rule.terms.allSatisfy({ $0.count <= 128 }),
                  !rule.keywords.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigurationError.invalid("关键词需为单行文本，每项最多 128 字符，每条规则最多 32 项。")
            }
        }
    }
}
public struct HighlightMatch: Equatable {
    public let range: NSRange
    public let color: HighlightColor
}
/// Bounded literal matching: custom text is escaped, never treated as executable regex.
public final class OutputHighlightMatcher {
    private var compiled: [(NSRegularExpression, HighlightColor)] = []
    public init(_ configuration: OutputHighlightConfiguration) throws {
        try configuration.validate()
        for rule in configuration.rules where rule.enabled && !rule.terms.isEmpty {
            let alternatives = rule.terms.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let literal = "(?:" + alternatives + ")"
            let pattern = rule.wholeWords ? "(?<![\\p{L}\\p{N}_])" + literal + "(?![\\p{L}\\p{N}_])" : literal
            let expression = try NSRegularExpression(pattern: pattern, options: rule.caseSensitive ? [] : [.caseInsensitive])
            compiled.append((expression, rule.color))
        }
    }
    public func matches(in text: String) -> [HighlightMatch] {
        let count = text.utf16.count
        guard count > 0, count <= 16384 else { return [] }
        var occupied = IndexSet(), result: [HighlightMatch] = []
        for (expression, color) in compiled {
            expression.enumerateMatches(in: text, range: NSRange(location: 0, length: count)) { match, _, _ in
                guard let range = match?.range, range.length > 0 else { return }
                let indices = IndexSet(integersIn: range.location..<NSMaxRange(range))
                guard occupied.intersection(indices).isEmpty else { return }
                occupied.formUnion(indices)
                result.append(HighlightMatch(range: range, color: color))
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }
}
