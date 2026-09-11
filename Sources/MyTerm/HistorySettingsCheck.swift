import AppKit
import MyTermCore

enum HistorySettingsCheck {
    static func run() throws {
        let preferences = HistoryPreferences.shared, original = HistoryPreferences.shared.policy
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-history-ui-\(UUID())")
        defer { preferences.policy = original; try? FileManager.default.removeItem(at: root) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("History settings: " + message) }
        }
        preferences.policy = HistoryPolicy()
        let model = HistoryModel(directory: root), repository = HistoryRepository(directory: root)
        let record = SessionHistory(id: UUID(), label: "test", started: Date(), text: "hello")
        model.save([record], wait: true)
        try require(try repository.ids().isEmpty, "Default settings wrote a log")
        preferences.policy.enabled = true
        model.save([record], wait: true)
        try require(try repository.load(record.id).text == "hello", "Opt-in did not save")
        preferences.policy.enabled = false
        model.save([SessionHistory(id: record.id, label: "test", started: record.started, text: "should not save")], wait: true)
        try require(try repository.load(record.id).text == "hello", "Disabled logging still wrote")
        model.setLoggingMode(.enabled, for: record.id)
        let forced = SessionHistory(id: record.id, label: "test", started: record.started, text: "forced on")
        model.save([forced], wait: true)
        try require(try repository.load(record.id).text == "forced on", "Session opt-in cannot override global off")
        preferences.policy.enabled = true
        model.setLoggingMode(.disabled, for: record.id)
        model.save([SessionHistory(id: record.id, label: "test", started: record.started, text: "forced off")], wait: true)
        try require(try repository.load(record.id).text == "forced on", "Session opt-out cannot override global on")
        model.setLoggingMode(.inherit, for: record.id)
        model.save([record], wait: true)
        try require(try repository.load(record.id).text == "hello", "Returning to inherit does not resume saving")
        let sibling = SessionHistory(id: UUID(), label: "sibling", started: Date(), text: "sibling on")
        model.setLoggingMode(.enabled, for: sibling.id)
        preferences.policy.enabled = false
        model.save([forced, sibling], wait: true)
        try require(try repository.load(record.id).text == "hello", "Global off did not affect inherited session")
        try require(try repository.load(sibling.id).text == sibling.text, "Global off affected independently enabled session")
        let terminal = TerminalSession(label: "test", executable: "/bin/bash", arguments: [])
        preferences.policy.maximumLines = 100
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        terminal.terminal.feed(text: (0..<300).map { "line\($0)\r\n" }.joined())
        let snapshot = terminal.historySnapshot().text
        try require(!snapshot.contains("line0\n") && snapshot.contains("line299"), "Live scrollback setting not applied")
        let export = root.appendingPathComponent("manual.txt")
        try HistoryRepository.export(snapshot, to: export)
        try require(try String(contentsOf: export, encoding: .utf8) == snapshot, "Manual export requires logging")
        print("PASS: history default off, live opt-in/out, scrollback settings and manual export")
    }
}
