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
