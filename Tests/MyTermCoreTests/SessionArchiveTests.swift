import Foundation
import MyTermCore

func checkSessionArchive() throws {
    var server = Server(name: "Test", host: "example.com", user: "alice", identityFile: "~/.ssh/id_ed25519", jumpHost: "relay")
    server.compression = true
    let group = SessionGroup(name: "Development", serverIDs: [server.id])
    let session = SavedSession(name: "Work", tabs: [SessionTab(server: server), SessionTab(directory: "/tmp")], selectedIndex: 1)
    let archive = SessionArchive(servers: [server], groups: [group], sessions: [session])
    let decoded = try SessionArchive.decode(archive.encoded())
    checkEqual(decoded.servers, [server]); checkEqual(decoded.groups, [group]); checkEqual(decoded.sessions, [session])
    let twice = try archive.merging(decoded)
    checkEqual(twice.servers.count, 1); checkEqual(twice.sessions.count, 1)
    let empty = SessionArchive(servers: [], groups: [], sessions: [])
    checkEqual(try empty.merging(decoded).groups, [group])
    var conflict = archive; conflict.servers[0].host = "changed.example.com"
    checkThrows(try archive.merging(conflict))
    var invalid = archive; invalid.version = 999
    checkThrows(try invalid.encoded())
    invalid = archive; invalid.sessions[0].selectedIndex = 100
    checkThrows(try invalid.encoded())
    invalid = archive; invalid.servers = []
    checkThrows(try invalid.encoded())
    invalid = archive; invalid.servers.append(server)
    checkThrows(try invalid.encoded())
    invalid = archive; invalid.servers[0].host = "-oProxyCommand=bad"
    checkThrows(try invalid.encoded())
    checkThrows(try SessionArchive.decode(Data("broken".utf8)))
    checkThrows(try SessionArchive.decode(Data(repeating: 32, count: 20 * 1024 * 1024 + 1)))
    let unrelated = SessionArchive(servers: [Server(host: "other.example.com")], groups: [], sessions: [])
    checkEqual(try archive.merging(unrelated).servers.count, 2)
}
