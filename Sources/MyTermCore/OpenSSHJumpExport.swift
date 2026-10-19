import Foundation
import CryptoKit

/// Export-only aliases. The runtime's per-session aliases remain private and unchanged.
/// Deduplicate complete effective options, never just IP or profile ID: the same profile
/// can need different first-hop proxies, authentication, compression or logging.
struct OpenSSHJumpExport {
    let chains: [[String]]
    let blocks: [String]

    init(servers: [Server], reserved: inout Set<String>) throws {
        struct Group {
            let options: [String]
            var names: Set<String>
            var sessions: Set<String>
        }
        var groups: [String: Group] = [:]
        var keys: [[String]] = []
        for server in servers {
            var chain: [String] = []
            for (index, hop) in (server.jumpServers ?? []).enumerated() {
                let options = hop.openSSHOptions(compression: server.compression ?? true,
                    debugLogging: server.debugLogging == true,
                    proxyCommand: index == 0 ? try server.proxy?.command() ?? "none" : "none")
                let key = options.joined(separator: "\n")
                var group = groups[key] ?? Group(options: options, names: [], sessions: [])
                group.names.insert(hop.displayName); group.sessions.insert(server.displayName)
                groups[key] = group; chain.append(key)
            }
            keys.append(chain)
        }
        var aliases: [String: String] = [:]
        var output: [(String, String)] = []
        for key in groups.keys.sorted() {
            let group = groups[key]!
            let label = group.names.sorted().first!
            let slug = OpenSSHExportAlias.slug(label)
            let digest = SHA256.hash(data: Data(key.utf8)).prefix(5).map { String(format: "%02x", $0) }.joined()
            let base = "myterm-jump-" + slug + "-" + digest
            var alias = base, suffix = 2
            while !reserved.insert(alias.lowercased()).inserted {
                alias = base + "-" + String(suffix); suffix += 1
            }
            aliases[key] = alias
            let comments = ["# Jump host: " + group.names.sorted().map(Self.comment).joined(separator: ", "),
                            "# Used by: " + group.sessions.sorted().map(Self.comment).joined(separator: ", ")]
            output.append((alias, (comments + ["Host " + alias] + group.options).joined(separator: "\n")))
        }
        chains = keys.map { $0.map { aliases[$0]! } }
        blocks = output.sorted { $0.0 < $1.0 }.map(\.1)
    }
    private static func comment(_ text: String) -> String {
        text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
    }
}
