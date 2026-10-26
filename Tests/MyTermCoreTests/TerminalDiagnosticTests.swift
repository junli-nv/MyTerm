import Foundation
import MyTermCore

func checkTerminalDiagnostics() throws {
    let log = TerminalDiagnosticLog(capacity: 3)
    let now = Date()
    log.record(.marker)
    checkEqual(log.snapshot().entries.count, 0)
    log.start(now: now)
    for count in 1...5 { log.record(.output, byteCount: count, now: now) }
    let snapshot = log.snapshot(now: now)
    checkEqual(snapshot.entries.map(\.byteCount), [3, 4, 5])
    checkEqual(snapshot.droppedEntries, 3)
    checkEqual(snapshot.recording, true)
    log.record(.marker, now: now.addingTimeInterval(900))
    checkFalse(log.snapshot(now: now.addingTimeInterval(900)).recording)
    checkEqual(log.snapshot().entries.count, 3)
    log.stop(now: now)
    checkFalse(log.isRecording(now: now))
    log.clear()
    checkEqual(log.snapshot().entries.count, 0)
    checkEqual(log.snapshot().started == nil, true)
    log.start(now: now)
    let encoded = try JSONEncoder().encode(log.snapshot(now: now))
    let decoded = try JSONDecoder().decode(TerminalDiagnosticLog.Snapshot.self, from: encoded)
    checkEqual(decoded.entries.first?.event, .started)
    let concurrent = TerminalDiagnosticLog(capacity: 10)
    concurrent.start()
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in concurrent.record(.marker) }
    checkEqual(concurrent.snapshot().entries.count, 10)
    checkEqual(concurrent.snapshot().droppedEntries, 991)
}

func checkMCPDiagnostics() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("mcp.json")
    let log = CodexMCPDiagnosticLog(url: url)
    log.record(.started)
    checkFalse(FileManager.default.fileExists(atPath: url.path))
    log.start()
    log.record(.started)
    log.record(.initializeReceived)
    log.record(.initializeReplied)
    log.record(.outputError, errorNumber: 32)
    checkEqual(log.snapshot().entries.map(\.event), [.started, .initializeReceived, .initializeReplied, .outputError])
    checkEqual(log.snapshot().entries.last?.errorNumber, 32)
    for _ in 0..<300 { log.record(.parseError) }
    checkEqual(log.snapshot().entries.count, 256)
    checkEqual(log.snapshot().dropped, 48)
    log.stop(); log.record(.inputEOF)
    checkEqual(log.snapshot().entries.last?.event, .parseError)
    log.start(now: Date().addingTimeInterval(-901)); log.record(.started)
    checkEqual(log.snapshot().entries.count, 0)
    checkFalse(log.snapshot().recording)
    log.clear(); checkEqual(log.snapshot().entries.count, 0)
    // A pre-existing symlink must never be followed or modified.
    let target = root.appendingPathComponent("target")
    try Data("private".utf8).write(to: target)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    log.start(); log.record(.started)
    checkEqual(try String(contentsOf: target, encoding: .utf8), "private")
}

func checkMCPHealthFailures() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = CodexMCPHealthCheck.run(executable: root.appendingPathComponent("missing"))
    checkFalse(missing.success); checkEqual(missing.stage.rawValue, "launch")
    let exited = CodexMCPHealthCheck.run(executable: URL(fileURLWithPath: "/usr/bin/false"))
    checkFalse(exited.success)
    let denied = root.appendingPathComponent("denied")
    try "#!/bin/bash\nexit 0\n".write(to: denied, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: denied.path)
    let permission = CodexMCPHealthCheck.run(executable: denied)
    checkFalse(permission.success); checkEqual(permission.reason, "permission_denied")
    let sleeper = root.appendingPathComponent("sleep")
    try "#!/bin/bash\nexec /bin/sleep 30\n".write(to: sleeper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sleeper.path)
    let timedOut = CodexMCPHealthCheck.run(executable: sleeper, timeout: 0.1)
    checkFalse(timedOut.success); checkEqual(timedOut.reason, "timeout")
    let invalid = root.appendingPathComponent("invalid")
    try "#!/bin/bash\nprintf 'not-json\\n'\n".write(to: invalid, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: invalid.path)
    let malformed = CodexMCPHealthCheck.run(executable: invalid)
    checkFalse(malformed.success)
}
