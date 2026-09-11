import Foundation
import Darwin

public struct SSHConfigCandidate: Identifiable, Equatable {
    public var id: String { alias }
    public let alias: String
    public let source: String
    public var server: Server { Server(name: alias, host: alias) }
}

/// Discover concrete Host aliases only. OpenSSH itself resolves Host/Match/Include on connection.
/// In particular, discovery never runs Match exec or ProxyCommand.
public struct SSHConfigImporter {
    public var root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")) { self.root = root }

    public func discover() throws -> [SSHConfigCandidate] {
        var seenFiles = Set<String>()
        var aliases = Set<String>()
        var candidates: [SSHConfigCandidate] = []
        func visit(_ url: URL, depth: Int) throws {
            guard depth < 32 else { throw ConfigurationError.invalid("SSH Include 层数过多。") }
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenFiles.insert(canonical).inserted else { return }
            let contents = try String(contentsOf: url, encoding: .utf8)
            for line in contents.components(separatedBy: .newlines) {
                let fields = Self.tokens(line)
                guard let key = fields.first?.lowercased() else { continue }
                if key == "host" {
                    for alias in fields.dropFirst() where !alias.contains(where: { "*?!".contains($0) }) {
                        guard (try? Server(host: alias).validated()) != nil, aliases.insert(alias).inserted else { continue }
                        candidates.append(SSHConfigCandidate(alias: alias, source: url.path))
                    }
                } else if key == "include" {
                    for pattern in fields.dropFirst() {
                        var expanded = (pattern as NSString).expandingTildeInPath
                        // Relative user Include paths are relative to ~/.ssh, not the included file.
                        if !expanded.hasPrefix("/") { expanded = root.deletingLastPathComponent().appendingPathComponent(expanded).path }
                        var matches = glob_t()
                        let result = glob(expanded, 0, nil, &matches)
                        defer { globfree(&matches) }
                        if result == GLOB_NOMATCH { continue }
                        guard result == 0 else { throw ConfigurationError.invalid("无法读取 Include：\(pattern)") }
                        for index in 0..<Int(matches.gl_pathc) {
                            if let path = matches.gl_pathv[index] { try visit(URL(fileURLWithPath: String(cString: path)), depth: depth + 1) }
                        }
                    }
                }
            }
        }
        try visit(root, depth: 0)
        return candidates.sorted { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }
    }

    static func tokens(_ line: String) -> [String] {
        var result: [String] = [], token = ""
        var quoted = false, escaped = false
        for char in line {
            if escaped { token.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "\"" { quoted.toggle(); continue }
            if !quoted && char == "#" { break }
            if !quoted && (char.isWhitespace || (char == "=" && result.count < 2)) {
                if !token.isEmpty { result.append(token); token = "" }
            } else { token.append(char) }
        }
        if escaped { token.append("\\") }
        if !token.isEmpty { result.append(token) }
        return result
    }
}
