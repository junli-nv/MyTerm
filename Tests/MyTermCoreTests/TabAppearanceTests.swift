import Foundation
import MyTermCore

func checkTabAppearance() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-tab-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = Server(host: "example.invalid")
    var reset = legacy; reset.tabAppearance = TabAppearance()
    checkEqual(try reset.validated(), legacy)
    let originalArguments = try legacy.sshArguments()
    var server = legacy
    server.tabAppearance = TabAppearance(color: .red, environment: " PROD ")
    server = try server.validated()
    checkEqual(server.tabAppearance?.environment, "PROD")
    checkEqual(try server.sshArguments(), originalArguments)
    checkThrows(try TabAppearance(environment: "bad\tlabel").validated())
    checkThrows(try TabAppearance(environment: String(repeating: "长", count: 25)).validated())
    let repo = ServerRepository(fileURL: root.appendingPathComponent("servers.json"))
    try repo.save([server])
    checkEqual(try repo.load().first?.tabAppearance, server.tabAppearance)
    checkEqual(try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(legacy)).tabAppearance, nil)
    var local = SessionTab(directory: "/tmp")
    local.tabAppearance = TabAppearance(color: .blue, environment: "LOCAL")
    let saved = SavedSession(name: "fixture", tabs: [local, SessionTab(server: server)], selectedIndex: 0)
    let archive = SessionArchive(servers: [server], groups: [], sessions: [saved])
    let decoded = try SessionArchive.decode(archive.encoded())
    checkEqual(decoded.servers.first?.tabAppearance, server.tabAppearance)
    checkEqual(decoded.sessions.first?.tabs.first?.tabAppearance, local.tabAppearance)
    let sessions = SessionRepository(url: root.appendingPathComponent("sessions.json"))
    try sessions.save([saved])
    checkEqual(try sessions.load().first?.tabs.first?.tabAppearance, local.tabAppearance)
}
