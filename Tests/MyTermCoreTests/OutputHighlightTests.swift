import Foundation
import MyTermCore

func checkOutputHighlight() throws {
    var config = OutputHighlightConfiguration()
    let matcher = try OutputHighlightMatcher(config)
    let text = "Error FAILED fail failure up active OK backup inactive lookup errors failedness"
    let matches = matcher.matches(in: text)
    checkEqual(matches.map { (text as NSString).substring(with: $0.range) }, ["Error", "FAILED", "fail", "failure", "up", "active", "OK"])
    checkEqual(matches[0].color, config.rules[0].color)
    checkEqual(matches[4].color, config.rules[1].color)
    config.rules = [.init(keywords: "not active, a+b, [fail], 故障", color: .init(10, 20, 30))]
    config.rules[0].wholeWords = false
    config.rules.append(.init(keywords: "active", color: .init(0, 255, 0)))
    let custom = try OutputHighlightMatcher(config)
    checkEqual(custom.matches(in: "not active a+b [fail] 发生故障").count, 4)
    checkEqual(custom.matches(in: "aaab").count, 0)
    config.rules[0].caseSensitive = true
    config.rules[0].keywords = "Error"
    checkEqual(try OutputHighlightMatcher(config).matches(in: "error Error").count, 1)
    config.rules[0].enabled = false
    checkEqual(try OutputHighlightMatcher(config).matches(in: "Error").count, 0)
    let restored = try JSONDecoder().decode(OutputHighlightConfiguration.self, from: JSONEncoder().encode(config))
    checkEqual(restored, config)
    config.rules[0].keywords = "bad\nrule"
    checkThrows(try config.validate())
    config.rules[0].keywords = String(repeating: "x", count: 129)
    checkThrows(try config.validate())
    checkEqual(matcher.matches(in: String(repeating: "Error ", count: 3000)).count, 0)
    let preferences = try PropertyListSerialization.data(fromPropertyList: ["terminal.outputHighlight": JSONEncoder().encode(restored)], format: .binary, options: 0)
    try PreferencesBackup(files: [:], preferences: preferences).validate()
    let invalid = try PropertyListSerialization.data(fromPropertyList: ["terminal.outputHighlight": Data("bad".utf8)], format: .binary, options: 0)
    checkThrows(try PreferencesBackup(files: [:], preferences: invalid).validate())
}
