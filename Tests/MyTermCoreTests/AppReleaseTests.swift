import Foundation
import MyTermCore

func checkAppRelease() throws {
    func release(_ tag: String, draft: Bool = false, pre: Bool = false) throws -> AppRelease {
        let object: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": pre, "body": "notes", "assets": [
            ["name": "MyTerm-3.10-macos-arm64.zip", "size": 3, "browser_download_url": "https://github.com/junli-nv/MyTerm/releases/download/v3.10/MyTerm-3.10-macos-arm64.zip"]]]
        return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: object))
    }
    checkEqual(try release("v3.10").newer(than: "3.9.9"), true)
    checkEqual(try release("3.2.0").newer(than: "3.2"), false)
    checkEqual(try release("3.1").newer(than: "3.2"), false)
    checkThrows(try release("3.3-beta").newer(than: "3.2"))
    checkThrows(try release("3.3", draft: true).newer(than: "3.2"))
    checkThrows(try release("3.3", pre: true).newer(than: "3.2"))
    checkEqual(AppRelease.version("3..2"), nil)
    checkEqual(AppRelease.version("3.99999999999999999999999999"), nil)
    checkEqual(try AppRelease.latestPageTag(URL(string: "https://github.com/junli-nv/MyTerm/releases/tag/v3.3")!), "v3.3")
    checkThrows(try AppRelease.latestPageTag(URL(string: "https://github.com/other/repo/releases/tag/v3.3")!))
    checkThrows(try AppRelease.latestPageTag(URL(string: "https://github.com/junli-nv/MyTerm/releases/tag/v3.3-beta")!))
    let current = try release("v3.10")
    checkEqual(try current.installer(architecture: "arm64").size, 3)
    checkThrows(try current.installer(architecture: "x86_64"))
    for bad in ["http://github.com/junli-nv/MyTerm/releases/download/v1/a.zip", "https://evil.example/junli-nv/MyTerm/releases/download/a", "https://github.com/other/repo/releases/download/a"] {
        checkEqual(AppRelease.trustedAssetURL(URL(string: bad)!), false)
    }
    let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    checkEqual(try AppRelease.checksum(hash + "  fixture.zip\n", named: "fixture.zip"), hash)
    checkThrows(try AppRelease.checksum(hash + "  other.zip", named: "fixture.zip"))
    checkThrows(try AppRelease.checksum(hash + "  fixture.zip\n" + hash + "  fixture.zip", named: "fixture.zip"))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("abc".utf8).write(to: file)
    try AppRelease.verify(file, digest: hash, size: 3)
    checkThrows(try AppRelease.verify(file, digest: hash, size: 4))
    try Data("def".utf8).write(to: file)
    checkThrows(try AppRelease.verify(file, digest: hash, size: 3))
}
