import Foundation
import MyTermCore

func checkJumpLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jump-library-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ServerRepository(fileURL: root.appendingPathComponent("servers.json"))
    var profile = SSHJumpServer(host: "jump.test", user: "alice", authentication: .password)
    let oldJSON = try JSONEncoder().encode(profile)
    checkEqual(try JSONDecoder().decode(SSHJumpServer.self, from: oldJSON).name, nil)
    var unnamedRoute = Server(host: "target.test", user: "root"); unnamedRoute.jumpServers = [profile]
    profile.editableName = "Dallas 跳板"
    var namedRoute = unnamedRoute; namedRoute.jumpServers = [profile]
    checkEqual(try SSHJumpCredentials.account(server: namedRoute, index: 0), try SSHJumpCredentials.account(server: unnamedRoute, index: 0))
    checkEqual(try SSHPasswordMemory.scopeIdentifier(for: namedRoute), try SSHPasswordMemory.scopeIdentifier(for: unnamedRoute))
    checkEqual(try SSHPasswordMemory.legacyScopeIdentifier(for: namedRoute), try SSHPasswordMemory.legacyScopeIdentifier(for: unnamedRoute))
    checkEqual(profile.displayName, "Dallas 跳板")
    var invalidName = profile; invalidName.editableName = "bad\nname"
    checkThrows(try invalidName.validated())
    invalidName.editableName = String(repeating: "a", count: 121)
    checkThrows(try invalidName.validated())
    var clearedName = profile; clearedName.editableName = "  "
    checkEqual(try clearedName.validated().displayName, profile.host)
    profile.profileID = profile.id
    try repository.save([], profiles: [profile])
    checkEqual(try repository.loadProfiles(), [profile])
    try repository.save([Server(host: "unrelated.test")])
    checkEqual(try repository.loadProfiles(), [profile]) // Ordinary edits must not drop unused profiles.
    let archive = SessionArchive(servers: [], groups: [], sessions: [], jumpProfiles: [profile])
    checkEqual(try SessionArchive.decode(archive.encoded()).jumpProfiles, [profile])
    checkEqual(try archive.merging(archive).jumpProfiles, [profile])
    let legacy = SessionArchive(servers: [], groups: [], sessions: [])
    checkEqual(try SessionArchive.decode(legacy.encoded()).jumpProfiles, nil)
    var bad = profile; bad.host = ""
    checkThrows(try repository.save([], profiles: [bad]))
    checkEqual(try repository.loadProfiles(), [profile])
    var route = Server(host: "destination.test")
    var predecessor = SSHJumpServer(host: "first.test", user: "bob")
    predecessor.profileID = predecessor.id
    var row = profile; row.id = UUID()
    route.jumpServers = [predecessor, row]
    let probe = try SSHJumpProbe(profile: profile, via: route, index: 1)
    checkEqual(probe.server.host, profile.host)
    checkEqual(probe.server.jumpServers, [predecessor])
    checkEqual(probe.passwordAccount, try SSHJumpCredentials.account(server: route, index: 1))
    checkEqual(probe.server.forwards, nil)
    let args = try probe.arguments(configPath: "/tmp/fixture", controlPath: "/tmp/private-probe/control")
    checkEqual(Array(args.suffix(2)), ["--", "jump.test"])
    checkEqual(args.contains("-N"), true)
    checkEqual(args.contains("ControlPersist=no"), true)
    checkEqual(args.contains("ClearAllForwardings=yes"), true)
    checkEqual(args.contains("ControlPath=/tmp/private-probe/control"), true)
    checkThrows(try SSHJumpProbe(profile: profile, via: route, index: 0))
    let direct = try SSHJumpProbe(profile: profile)
    checkEqual(direct.server.jumpHost, "none")
    checkEqual(direct.server.proxy, nil)
    checkEqual(direct.server.jumpServers, nil)
    var snapshot = route; snapshot.jumpServers = [row]
    profile.port = "2222"
    checkEqual(SharedSSHJumps.resolving(snapshot, from: [], profiles: [profile]).jumpServers![0].port, "2222")
    try repository.save([], profiles: [])
    checkEqual(try repository.loadProfiles(), [])
}
