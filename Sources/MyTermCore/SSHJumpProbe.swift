import Foundation

/// A hop is tested as the destination, through only the hops preceding it.
public struct SSHJumpProbe {
    public let server: Server
    public let passwordAccount: String?
    public init(profile: SSHJumpServer, via route: Server? = nil, index: Int? = nil) throws {
        let hop = try profile.validated()
        var path = route ?? Server(host: "probe.invalid")
        if let index {
            guard let hops = route?.jumpServers, hops.indices.contains(index), hops[index].profileID == hop.id else {
                throw ConfigurationError.invalid("测试路径已变化，请重新选择。")
            }
            path.jumpServers = Array(hops.prefix(index)) + [hop]
        } else { path.jumpServers = [hop]; path.proxy = nil }
        passwordAccount = try? SSHJumpCredentials.account(server: path, index: path.jumpServers!.count - 1)
        var target = Server(name: SSHJumpCredentials.label(hop), host: hop.host, user: hop.user, port: hop.port, identityFile: hop.identityFile)
        target.authentication = hop.authentication
        let preceding = Array(path.jumpServers!.dropLast())
        target.jumpServers = preceding.isEmpty ? nil : preceding
        target.jumpHost = preceding.isEmpty ? "none" : nil
        target.proxy = path.proxy
        target.x11Forwarding = .disabled
        server = try target.validated()
    }
    public func arguments(configPath: String?, controlPath: String) throws -> [String] {
        ["-N", "-T", "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1", "-o", "ClearAllForwardings=yes",
         "-o", "RemoteCommand=none", "-o", "ControlMaster=yes", "-o", "ControlPersist=no", "-o", "ControlPath=\(controlPath)"]
        + (try server.connectionArguments(configPath: configPath)) + ["--", server.host]
    }
}
