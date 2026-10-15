import Foundation
import MyTermCore

private final class UpdateFixtureProtocol: URLProtocol {
    static var statusCode = 200
    static var payload = Data()
    static var pageFallback = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fallback = Self.pageFallback && request.url?.host == "github.com"
        let response = HTTPURLResponse(url: fallback ? URL(string: "https://github.com/junli-nv/MyTerm/releases/tag/v3.1")! : request.url!,
            statusCode: fallback ? 200 : Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum AppUpdateCheck {
    static func run() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateFixtureProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let model = AppUpdateModel(current: "3.2.2", network: network)
        func check() throws {
            model.check()
            let deadline = Date().addingTimeInterval(3)
            while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard !model.busy else { throw ConfigurationError.invalid("Update check timed out") }
        }
        func require(_ value: Bool) throws { if !value { throw ConfigurationError.invalid("Update status regression") } }
        UpdateFixtureProtocol.payload = Data(#"{"tag_name":"v3.3","draft":false,"prerelease":false,"body":"fixture notes","assets":[]}"#.utf8)
        try check(); try require(model.available && model.release?.body == "fixture notes")
        UpdateFixtureProtocol.payload = Data(#"{"tag_name":"v3.1","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        try check(); try require(!model.available && model.release != nil)
        for code in [403, 404, 429, 500] {
            UpdateFixtureProtocol.statusCode = code
            try check(); try require(!model.available && model.release == nil && model.status.contains(String(code)))
        }
        UpdateFixtureProtocol.statusCode = 403; UpdateFixtureProtocol.pageFallback = true
        try check(); try require(!model.available && model.release?.tag_name == "v3.1")
        UpdateFixtureProtocol.pageFallback = false
        UpdateFixtureProtocol.statusCode = 200
        UpdateFixtureProtocol.payload = Data("invalid json".utf8)
        try check(); try require(!model.available && model.release == nil)
        // Validate the actual packaged app without requiring developer tools on user Macs.
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("myterm-update-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("update.zip")
        let source = root.appendingPathComponent("MyTerm.app")
        try AppUpdatePreparation.run("/usr/bin/ditto", [Bundle.main.bundleURL.path, source.path])
        try AppUpdatePreparation.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
        let identifier = Bundle.main.bundleIdentifier!
        _ = try AppUpdatePreparation.prepare(root: root, version: version, identifier: identifier, architecture: architecture)
        var rejected = false
        do { _ = try AppUpdatePreparation.prepare(root: root, version: "999.0", identifier: identifier, architecture: architecture) }
        catch { rejected = true }
        try require(rejected)
        if ProcessInfo.processInfo.environment["MYTERM_LIVE_UPDATE_CHECK"] == "1" {
            let live = AppUpdateModel()
            live.check()
            let deadline = Date().addingTimeInterval(90)
            while live.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
            guard !live.busy, let release = live.release else { live.cancel(); throw ConfigurationError.invalid("Live update check: " + live.status) }
            print("PASS: live update lookup: \(release.tag_name), update available=\(live.available)")
        }
        print("PASS: updater HTTP fixtures: newer/current versions, release notes, rate limits, HTTP errors and malformed responses")
    }
}
