import Foundation
import MyTermCore

func checkTrzsz() throws {
    let root = URL(fileURLWithPath: "/tmp/myterm-trzsz-core-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("中文 '$() file")
    try Data([0, 255]).write(to: file)
    let input = String(decoding: try TrzszIntegration.dragInput([file, root]), as: UTF8.self)
    checkEqual(input, "'\(root.path)/中文 '\\''$() file' '\(root.path)' ")
    checkFalse(input.contains("\n"))
    checkThrows(try TrzszIntegration.dragInput([]))
    checkThrows(try TrzszIntegration.dragInput([URL(string: "https://example.com/file")!]))
    let invalid = root.appendingPathComponent("bad\nname")
    try Data().write(to: invalid)
    checkThrows(try TrzszIntegration.dragInput([invalid]))
    let args = ["-i", file.path, "-J", "user@jump:2222", "user@host"]
    checkEqual(TrzszIntegration.arguments(sshArguments: args), ["--dragfile", "/usr/bin/ssh"] + args)
    var server = Server(host: "example.com")
    checkEqual(server.trzszEnabled ?? true, true)
    checkEqual(server.dragUploadProtocol ?? .automatic, .automatic)
    server.trzszEnabled = false; server.dragUploadProtocol = .trzsz
    let restored = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(server))
    checkEqual(restored.trzszEnabled, false)
    checkEqual(restored.dragUploadProtocol, .trzsz)
}
