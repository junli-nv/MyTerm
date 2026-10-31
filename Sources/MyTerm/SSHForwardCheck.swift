import AppKit
import SwiftUI
import MyTermCore

/// Initial authentication wait, independent failures, toggles and stale replies.
enum SSHForwardCheck {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("SSH forwarding: " + message) }
        }
        func settle(_ model: SSHForwardModel) throws {
            let deadline = Date().addingTimeInterval(2)
            while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            try require(!model.busy, "Control operation blocked")
        }
        let lock = NSLock()
        var ready = false, fail = false, delay = false, uncertain = false
        let model = SSHForwardModel { _, operation, _ in
            lock.lock(); let values = (ready, fail, delay, uncertain); lock.unlock()
            if values.2 { Thread.sleep(forTimeInterval: 0.1) }
            return .init(succeeded: values.0 && !values.3 && !(values.1 && operation == .forward), uncertain: values.3, detail: values.3 ? "" : "Fixture")
        }
        let rule = PortForward(), context = try SSHLaunchContext(server: Server(host: "fixture.invalid"))
        model.start(rules: [rule, PortForward()], context: context)
        try settle(model)
        try require(model.entries.count == 1 && model.entries[0].state == .waiting && !model.connected,
                    "Initial state or duplicate listener incorrect")
        lock.lock(); ready = true; fail = true; lock.unlock()
        model.refresh(); try settle(model)
        try require(model.connected && model.entries[0].state == .failed, "Failure lost transport")
        lock.lock(); fail = false; lock.unlock()
        model.setEnabled(true, id: rule.id); try settle(model)
        try require(model.entries[0].state == .enabled, "Retry failed")
        let language = LanguagePreferences.shared, previous = LanguagePreferences.shared.selection
        defer { language.selection = previous }
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            let host = NSHostingView(rootView: SSHForwardView(model: model).environment(\.locale, language.locale))
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
            host.layoutSubtreeIfNeeded()
            try require(host.fittingSize.width <= 500 && host.fittingSize.height <= 340, "Forwarding panel exceeds its bounds")
            if let directory = ProcessInfo.processInfo.environment["MYTERM_CHECK_SNAPSHOTS"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    URL(fileURLWithPath: directory).appendingPathComponent("ssh-forward-\(locale.rawValue).png"))
            }
        }
        model.setEnabled(false, id: rule.id); try settle(model)
        try require(model.entries[0].state == .disabled, "Disable failed")
        model.refresh(); try settle(model)
        try require(model.entries[0].state == .disabled, "Health check re-enabled a disabled listener")
        lock.lock(); uncertain = true; lock.unlock()
        model.setEnabled(true, id: rule.id); try settle(model)
        try require(model.entries[0].state == .unknown && !model.entries[0].detail.isEmpty, "Timeout lacks explanation")
        lock.lock(); uncertain = false; ready = false; lock.unlock()
        model.refresh(); try settle(model)
        try require(!model.connected && model.entries[0].state == .disconnected, "Lost transport still enabled")
        lock.lock(); ready = true; lock.unlock()
        model.refresh(); try settle(model)
        lock.lock(); delay = true; lock.unlock()
        model.setEnabled(true, id: rule.id)
        model.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try require(model.entries[0].state == .disconnected && !model.connected, "Late reply revived stopped transport")
        print("PASS: SSH forwarding state, failure, retry, disable, deduplication and stop generation")
    }
}
