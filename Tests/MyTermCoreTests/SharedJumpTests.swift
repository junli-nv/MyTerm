import Foundation
import MyTermCore

func checkSharedJumps() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-shared-jumps-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = ServerRepository(fileURL: root.appendingPathComponent("servers.json"))
    var first = Server(name: "A", host: "a.test", user: "root")
    first.jumpServers = [SSHJumpServer(host: "192.0.2.1", user: "jump", authentication: .password)]
    var second = Server(name: "B", host: "b.test", user: "root")
    second.jumpServers = [SSHJumpServer(host: "192.0.2.1", user: "jump", authentication: .password)]
    var independent = second; independent.id = UUID(); independent.jumpServers![0].authentication = .key
    let original = [first, second, independent]
    let oldBytes = try JSONEncoder().encode(original)
    try oldBytes.write(to: repository.fileURL)
    let shared = try repository.load()
    let profile = shared[0].jumpServers![0].profileID!
    checkEqual(profile, shared[1].jumpServers![0].profileID)
    checkFalse(profile == shared[2].jumpServers![0].profileID)
    let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
    checkEqual(backups.count, 1)
    checkEqual(try Data(contentsOf: backups[0]), oldBytes)
    checkEqual(try repository.load(), shared)
    for (old, new) in zip(original, shared) {
        checkEqual(old.jumpServers![0].id, new.jumpServers![0].id)
        checkEqual(try SSHJumpCredentials.account(server: old, index: 0), try SSHJumpCredentials.account(server: new, index: 0))
        checkEqual(try SSHPasswordMemory.scopeIdentifier(for: old), try SSHPasswordMemory.scopeIdentifier(for: new))
        checkEqual(try SSHPasswordMemory.legacyScopeIdentifier(for: old), try SSHPasswordMemory.legacyScopeIdentifier(for: new))
    }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL)) as! [String: Any]
    checkEqual((object["profiles"] as! [Any]).count, 2)
    let entries = object["entries"] as! [[String: Any]]
    checkEqual((entries[0]["server"] as! [String: Any])["jumpServers"] == nil, true)
    var edited = shared[0]; edited.jumpServers![0].port = "2222"
    let updated = try SharedSSHJumps.normalized(SharedSSHJumps.applying(edited, to: shared))
    checkEqual(updated[1].jumpServers![0].port, "2222")
    checkEqual(updated[2].jumpServers![0].port, "22")
    checkEqual(SharedSSHJumps.resolving(shared[1], from: updated).jumpServers![0].port, "2222")
    var detached = shared[0]; detached.jumpServers![0].profileID = UUID()
    let separate = try SharedSSHJumps.normalized(SharedSSHJumps.applying(detached, to: shared))
    checkFalse(separate[0].jumpServers![0].profileID == separate[1].jumpServers![0].profileID)
    var conflict = shared; conflict[1].jumpServers![0].host = "other.test"
    checkThrows(try repository.save(conflict))
    checkEqual(try repository.load(), shared)
    let archive = SessionArchive(servers: shared, groups: [], sessions: [])
    checkEqual(try SessionArchive.decode(archive.encoded()).servers, shared)
    var badObject = object; badObject["profiles"] = []
    let badBytes = try JSONSerialization.data(withJSONObject: badObject)
    try badBytes.write(to: repository.fileURL)
    checkThrows(try repository.load())
    checkEqual(try Data(contentsOf: repository.fileURL), badBytes)
    // Different preceding routes must not be merged automatically.
    var via = second
    via.jumpServers!.insert(SSHJumpServer(host: "192.0.2.2", user: "jump"), at: 0)
    let routes = try SharedSSHJumps.normalized([first, via])
    checkFalse(routes[0].jumpServers![0].profileID == routes[1].jumpServers![1].profileID)
}
