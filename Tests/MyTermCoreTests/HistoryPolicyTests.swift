import Foundation
import MyTermCore

func checkHistoryPolicy() throws {
    func checkTrue(_ value: Bool) { checkEqual(value, true) }
    for global in [false, true] {
        checkEqual(HistoryLoggingMode.inherit.resolves(global: global), global)
        checkEqual(HistoryLoggingMode.enabled.resolves(global: global), true)
        checkEqual(HistoryLoggingMode.disabled.resolves(global: global), false)
    }
    var server = Server(name: "test", host: "example.com")
    for mode in HistoryLoggingMode.allCases {
        server.historyLogging = mode
        let restored = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(server))
        checkEqual(restored.historyLogging, mode)
        let tabs = [SessionTab(server: server, historyLogging: mode), SessionTab(directory: "/tmp", historyLogging: mode)]
        checkEqual(try JSONDecoder().decode([SessionTab].self, from: JSONEncoder().encode(tabs)), tabs)
    }
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as! [String: Any]
    legacy.removeValue(forKey: "historyLogging")
    checkEqual(try JSONDecoder().decode(Server.self, from: JSONSerialization.data(withJSONObject: legacy)).historyLogging, nil)
    checkEqual(try JSONDecoder().decode(SessionTab.self, from: Data("{}".utf8)).historyLogging, nil)
    var policy = HistoryPolicy()
    checkFalse(policy.enabled)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = HistoryRepository(directory: root)
    let record = SessionHistory(id: UUID(), label: "中文", started: Date(), text: (0..<200).map(String.init).joined(separator: "\n") + "\n")
    try repo.save(record, policy: policy)
    checkFalse(FileManager.default.fileExists(atPath: root.path))
    policy.enabled = true; policy.maximumLines = 100; policy.compressed = false
    try repo.save(record, policy: policy)
    checkEqual(try repo.load(record.id).text, (100..<200).map(String.init).joined(separator: "\n") + "\n")
    policy.fileMiB = 1; policy.totalMiB = 1
    let huge = SessionHistory(id: UUID(), label: "Unicode", started: Date(), text: String(repeating: "中文😀\t\"", count: 150_000))
    let data = try policy.archiveData(huge)
    checkTrue(data.count <= 1024 * 1024)
    let decoded = try JSONDecoder().decode(SessionHistory.self, from: data)
    checkTrue(huge.text.hasSuffix(decoded.text)); checkFalse(decoded.text.isEmpty)
    try repo.save(huge, policy: policy)
    let old = root.appendingPathComponent(record.id.uuidString + ".json")
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: old.path)
    let filler = SessionHistory(id: UUID(), label: "filler", started: Date(), text: String(repeating: "x", count: 200_000))
    try repo.save(filler, policy: policy)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: root.appendingPathComponent(filler.id.uuidString + ".json").path)
    try repo.enforceCapacity(policy)
    checkFalse(try repo.ids().contains(record.id))
    checkTrue(try repo.ids().contains(huge.id))
    try Data("keep".utf8).write(to: root.appendingPathComponent("unrelated.txt"))
    checkTrue(try repo.clean(before: Date.distantPast).isEmpty)
    checkEqual(try repo.clean(), Set([huge.id]))
    checkTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("unrelated.txt").path))
    policy.totalMiB = 20; policy.compressed = true
    let start = Date()
    try repo.save(huge, policy: policy)
    checkEqual(try repo.load(huge.id).text, huge.text)
    let compressedURL = root.appendingPathComponent(huge.id.uuidString + ".json.gz")
    checkTrue(try Data(contentsOf: compressedURL).count < huge.text.utf8.count / 10)
    print("gzip round trip: \(String(format: "%.3f", Date().timeIntervalSince(start))) seconds, \(huge.text.utf8.count) input bytes")
    let gzip = Process()
    gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); gzip.arguments = ["-t", compressedURL.path]
    try gzip.run(); gzip.waitUntilExit(); checkEqual(gzip.terminationStatus, 0)
    var corrupt = try Data(contentsOf: compressedURL); corrupt.removeLast(5)
    try corrupt.write(to: compressedURL); checkThrows(try repo.load(huge.id))
    // Writing uncompressed migrates this record and removes the damaged compressed copy.
    policy.compressed = false; try repo.save(record, policy: policy)
    policy.compressed = true; try repo.save(record, policy: policy)
    checkFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(record.id.uuidString + ".json").path))
    // Incompressible text exercises the compressed-byte cap, not only raw JSON limits.
    var seed: UInt64 = 1234567
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    let noise = String(decoding: (0..<1_800_000).map { _ -> UInt8 in
        seed = seed &* 6364136223846793005 &+ 1
        return alphabet[Int(seed >> 58)]
    }, as: UTF8.self)
    let noisy = SessionHistory(id: UUID(), label: "noise", started: Date(), text: noise)
    try repo.save(noisy, policy: policy)
    let noisyData = try Data(contentsOf: root.appendingPathComponent(noisy.id.uuidString + ".json.gz"))
    checkTrue(noisyData.count <= 1024 * 1024)
    let noisyText = try repo.load(noisy.id).text
    checkFalse(noisyText.isEmpty); checkTrue(noise.hasSuffix(noisyText)); checkTrue(noisyText.count < noise.count)
    policy.maximumLines = 0; checkThrows(try policy.validate())
    policy.maximumLines = 100; policy.fileMiB = 2; policy.totalMiB = 1; checkThrows(try policy.validate())
}
