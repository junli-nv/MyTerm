import AppKit
import MyTermCore

enum JumpProbeCheck {
    private struct Fixture: Decodable {
        let profile: SSHJumpServer
        let route: Server?
        let index: Int?
        let configPath: String
        let credentials: String
        let password: String?
        let useDraft: Bool?
        let expectSuccess: Bool
        let cancel: Bool
    }
    static func run(path: String) {
        do {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            let probe = try SSHJumpProbe(profile: fixture.profile, via: fixture.route, index: fixture.index)
            let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
            let test = JumpConnectionTest()
            let start = Date()
            let store = SQLitePasswordStore(directory: URL(fileURLWithPath: fixture.credentials))
            if let password = fixture.password, let account = probe.passwordAccount { try store.save(fixture.useDraft == true ? "unchanged-stored-password" : password, account: account) }
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                test.start(probe, configPath: fixture.configPath, store: store, password: fixture.useDraft == true ? fixture.password ?? "" : "")
                if fixture.cancel { test.cancel() }
            }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if !test.running && !test.result.isEmpty {
                    guard test.succeeded == fixture.expectSuccess,
                          fixture.expectSuccess || (fixture.cancel ? test.result == L10n.text("测试已取消。") : test.result.contains("Permission denied")) else { fputs("FAIL: jump probe outcome\n", stderr); exit(1) }
                    if fixture.useDraft == true, let account = probe.passwordAccount,
                       (try? store.read(account)) != "unchanged-stored-password" { fputs("FAIL: test persisted draft password\n", stderr); exit(1) }
                    print("PASS: real jump probe result, expected success=\(fixture.expectSuccess), cancelled=\(fixture.cancel)")
                    exit(0)
                }
                if Date().timeIntervalSince(start) > 15 { test.cancel(); fputs("FAIL: jump probe timeout\n", stderr); exit(1) }
            }
            withExtendedLifetime(test) { app.run() }
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
