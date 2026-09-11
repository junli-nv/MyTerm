import Foundation

public enum OpenSSHExport {
    public static func render(_ servers: [Server], userConfig: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config").path) throws -> String {
        func quote(_ value: String) throws -> String {
            guard !value.contains("\n"), !value.contains("\r"), !value.contains("\0") else { throw ConfigurationError.invalid("配置值包含换行符。") }
            return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var seen = Set<String>(), blocks: [String] = [], jumpBlocks: [String] = []
        for original in servers {
            let server = try original.validated()
            guard seen.insert(server.host.lowercased()).inserted else { throw ConfigurationError.invalid("多个会话使用相同主机或别名 \(server.host)，请先为它们设置不同的 SSH 别名再导出。") }
            var lines = ["# " + server.displayName.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "), "Host \(server.host)"]
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
        return "# MyTerm OpenSSH configuration. Use: ssh -F <this-file> <Host>\n# Keep referenced private keys, MyTermProxy (when used), and included SSH configs available.\n\n" + (blocks + jumpBlocks).joined(separator: "\n\n") + "\n\nHost *\n    Include \(try quote(userConfig))\n    Include /etc/ssh/ssh_config\n"
    }
}
