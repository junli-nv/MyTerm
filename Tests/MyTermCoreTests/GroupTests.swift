import Foundation
import MyTermCore

func checkSessionGroups() throws {
    let directory = URL(fileURLWithPath: "/tmp/myterm-groups-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = SessionGroupRepository(url: directory.appendingPathComponent("groups.json"))
    checkEqual(SessionGroup.normalizedName("\u{200B}生产\u{0000}环境\u{FEFF}"), "生产环境")
    checkEqual(SessionGroup.normalizedName("生产\t环境\r\n"), "生产 环境")
    checkEqual(SessionGroup.normalizedName("\u{200B}\u{0000}\u{FEFF}"), "")
    checkEqual(try repository.load(), [])
    let server = UUID()
    var groups = [SessionGroup(name: "生产环境"), SessionGroup(name: "测试环境")]
    groups = try SessionGroupRepository.moving(server, to: groups[0].id, in: groups)
    groups = try SessionGroupRepository.moving(server, to: groups[1].id, in: groups)
    checkEqual(groups[0].serverIDs, []); checkEqual(groups[1].serverIDs, [server])
    groups[1].name = "开发环境"; groups[1].collapsed = true
    try repository.save(groups); checkEqual(try repository.load(), groups)
    checkThrows(try repository.save(groups + [SessionGroup(name: "开发环境")]))
    checkEqual(try repository.load(), groups) // Failed edits preserve the prior file.
    checkThrows(try repository.save([SessionGroup(name: " ")]))
    checkThrows(try repository.save([SessionGroup(name: "未分组")]))
    try SessionGroupRepository.validate([SessionGroup(name: String(repeating: "中", count: 60))])
    checkThrows(try SessionGroupRepository.validate([SessionGroup(name: String(repeating: "中", count: 61))]))
    checkThrows(try SessionGroupRepository.validate([SessionGroup(name: "生产\n环境")]))
    checkThrows(try SessionGroupRepository.moving(server, to: UUID(), in: groups))
    groups = try SessionGroupRepository.moving(server, to: nil, in: groups)
    checkEqual(groups.flatMap(\.serverIDs), [])
    groups.removeFirst(); try repository.save(groups)
    checkEqual(try repository.load().count, 1)
    try Data("invalid".utf8).write(to: repository.url)
    checkThrows(try repository.load())
    checkEqual(repository.loadForStartup(), [])
    checkEqual(try String(contentsOf: repository.url, encoding: .utf8), "invalid")
    try repository.save([SessionGroup(name: "恢复后新建")])
    let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("groups-recovery-") }
    checkEqual(backups.count, 1)
    checkEqual(try String(contentsOf: backups[0], encoding: .utf8), "invalid")
    checkEqual(try repository.load().map(\.name), ["恢复后新建"])
    let legacy: [[String: Any]] = [
        ["id": UUID().uuidString, "name": "原有分组", "serverIDs": [server.uuidString]],
        ["name": ""], ["name": "原有分组"],
        ["name": "另一个分组", "serverIDs": [server.uuidString, server.uuidString]],
        ["name": "空分组"]
    ]
    let original = try JSONSerialization.data(withJSONObject: legacy)
    try original.write(to: repository.url)
    let recovered = repository.loadForStartup()
    checkEqual(recovered.map(\.name), ["原有分组", "另一个分组", "空分组"])
    checkEqual(recovered.flatMap(\.serverIDs), [server])
    checkEqual(recovered[0].collapsed, false)
    checkEqual(try Data(contentsOf: repository.url), original)
    for contents in ["", "null", "{}", "[]"] {
        try Data(contents.utf8).write(to: repository.url)
        checkEqual(repository.loadForStartup(), [])
    }
}
