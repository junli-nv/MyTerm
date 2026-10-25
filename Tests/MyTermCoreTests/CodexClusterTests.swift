import Foundation
import MyTermCore

func checkCodexClusters() throws {
    let threadID = UUID().uuidString, association = UUID()
    let arguments = try CodexConnection.launchArguments(appExecutable: "/tmp/MyTerm.app/MyTerm", association: association,
        threadID: threadID, projectDirectory: "/tmp/GMI Dallas 集群")
    checkEqual(Array(arguments.suffix(4)), ["--cd", "/tmp/GMI Dallas 集群", "resume", threadID])
    checkEqual(arguments.contains("read-only"), true)
    checkEqual(arguments.contains("mcp_servers.myterm.env.MYTERM_CODEX_ASSOCIATION=\"" + association.uuidString + "\""), true)
    checkThrows(try CodexConnection.launchArguments(appExecutable: "/tmp/app", threadID: "--all", projectDirectory: "/tmp"))
    checkThrows(try CodexConnection.launchArguments(appExecutable: "/tmp/app", threadID: threadID))
    checkThrows(try CodexConnection.launchArguments(appExecutable: "/tmp/app", localDirectory: "/tmp", threadID: threadID, projectDirectory: "/tmp"))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-clusters-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    var catalog = CodexClusterCatalog()
    let dallas = try catalog.addCluster("GMI Dallas")
    let london = try catalog.addCluster("GMI London")
    checkEqual(try catalog.addCluster("gmi dallas").id, dallas.id)
    checkFalse(dallas.folder.contains("/"))
    let longName = try catalog.addCluster(String(repeating: "集", count: 100))
    checkEqual(longName.folder.utf8.count < 255, true)
    checkEqual(try catalog.uniqueTitle("日常运维", cluster: dallas.id), "日常运维")
    checkThrows(try catalog.addCluster("\n"))
    checkThrows(try catalog.addCluster("bad\tname"))
    let now = Date(timeIntervalSince1970: 1792910000)
    let thread = UUID().uuidString
    catalog.conversations.append(.init(id: thread, clusterID: dallas.id, title: "日常运维", lastOpened: now))
    let name = try catalog.uniqueTitle("日常运维", cluster: dallas.id, now: now)
    checkEqual(name.hasPrefix("日常运维 · "), true)
    checkEqual(name.contains(":"), true)
    checkFalse(name.contains("(2)"))
    checkEqual(try catalog.uniqueTitle("日常运维", cluster: london.id), "日常运维")
    catalog.conversations.append(.init(id: UUID().uuidString, clusterID: dallas.id, title: name, lastOpened: now))
    checkFalse(try catalog.uniqueTitle("日常运维", cluster: dallas.id, now: now) == name)
    let server = UUID().uuidString; catalog.serverClusters[server] = dallas.id
    let url = root.appendingPathComponent("catalog.json")
    try catalog.save(to: url)
    let loaded = try CodexClusterCatalog.load(from: url)
    checkEqual(loaded.clusters, catalog.clusters)
    checkEqual(loaded.conversations, catalog.conversations)
    checkEqual(loaded.serverClusters[server], dallas.id)
    // Session metadata is independent of the transient SSH tab UUID.
    checkEqual(loaded.conversations[0].id, thread)
    try Data("damaged".utf8).write(to: url)
    checkThrows(try CodexClusterCatalog.load(from: url))
    checkEqual(try String(contentsOf: url, encoding: .utf8), "damaged")
}
