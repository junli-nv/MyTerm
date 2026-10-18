import Foundation

public enum OpenSSHExport {
    public static func render(_ servers: [Server], userConfig: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config").path) throws -> String {
        func quote(_ value: String) throws -> String {
            guard !value.contains("\n"), !value.contains("\r"), !value.contains("\0") else { throw ConfigurationError.invalid("配置值包含换行符。") }
            return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let validated = try servers.map { try $0.validated() }
        let counts = Dictionary(grouping: validated, by: { $0.host.lowercased() }).mapValues(\.count)
        // Reserve every original destination before allocating aliases, including later entries.
        var reserved = Set(validated.map { $0.host.lowercased() })
        var blocks: [String] = [], jumpBlocks: [String] = []
        for server in validated {
            var alias = server.host
            if counts[server.host.lowercased(), default: 0] > 1 {
                let base = "myterm-" + server.id.uuidString.lowercased()
                alias = base
                var suffix = 2
                while !reserved.insert(alias.lowercased()).inserted {
                    alias = base + "-" + String(suffix); suffix += 1
                }
            }
            var lines = ["# " + server.displayName.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "), "Host \(alias)"]
            if alias != server.host { lines.append("    HostName " + (try quote(server.host))) }
            let args = try server.connectionArguments()
            if server.debugLogging == true { lines.append("    LogLevel DEBUG3") }
            var index = 0
            while index < args.count {
                let flag = args[index], value = args[index + 1]; index += 2
                if flag == "-o" {
                    let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts[0] == "ProxyCommand" { lines.append("    ProxyCommand " + parts[1]) }
                    else { lines.append("    " + parts[0] + " " + (try quote(parts[1]))) }
                } else if let keyword = ["-p": "Port", "-l": "User", "-i": "IdentityFile", "-J": "ProxyJump"][flag] {
                    // ProxyJump parses its own comma-separated syntax and preserves quotes literally.
                    lines.append("    " + keyword + " " + (flag == "-J" ? value : try quote(value)))
                }
            }
            for forward in server.forwards ?? [] {
                _ = try forward.arguments()
                func endpoint(_ host: String, _ port: String) -> String { (host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host) + ":" + port }
                let listener = endpoint(forward.bindAddress, forward.listenPort)
                if forward.kind == .dynamic { lines.append("    DynamicForward \(listener)") }
                else { lines.append("    \(forward.kind == .local ? "LocalForward" : "RemoteForward") \(listener) \(endpoint(forward.destinationHost, forward.destinationPort))") }
            }
            if !(server.forwards ?? []).isEmpty { lines.append("    ExitOnForwardFailure yes") }
            blocks.append(lines.joined(separator: "\n"))
            if let jump = try server.proxyJumpConfig(userConfig: userConfig), let range = jump.range(of: "\nHost *") {
                jumpBlocks.append(String(jump[..<range.lowerBound]))
            }
        }
        return "# MyTerm OpenSSH configuration. Use: ssh -F <this-file> <Host>\n# Keep referenced private keys, MyTermProxy (when used), and included SSH configs available.\n# Generated myterm-* aliases use the original destination as HostName. Host-specific settings\n# inherited from included configs must also match the generated alias; alias destinations\n# need their real HostName supplied on the destination machine.\n\n" + (blocks + jumpBlocks).joined(separator: "\n\n") + "\n\nHost *\n    Include \(try quote(userConfig))\n    Include /etc/ssh/ssh_config\n"
    }
}
