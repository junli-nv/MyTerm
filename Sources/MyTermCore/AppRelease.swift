import Foundation
import CryptoKit

/// Only stable numeric releases from this repository can be offered for installation.
public struct AppRelease: Decodable {
    public struct Asset: Decodable {
        public let name: String
        public let browser_download_url: URL
        public let size: Int64
        public let digest: String?
    }
    public let tag_name: String
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public init(tag: String, notes: String?, assets: [Asset]) {
        tag_name = tag; body = notes; self.assets = assets; draft = false; prerelease = false
    }
    public static func latestPageTag(_ url: URL) throws -> String {
        let prefix = "/junli-nv/MyTerm/releases/tag/"
        guard url.scheme == "https", url.host == "github.com", url.path.hasPrefix(prefix), url.user == nil, url.password == nil,
              let tag = url.path.components(separatedBy: prefix).last, version(tag) != nil else {
            throw ConfigurationError.invalid("无法识别正式发布版本。")
        }
        return tag
    }
    public static func fallbackAsset(tag: String, architecture: String, size: Int64) -> Asset {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let name = "MyTerm-\(version)-macos-\(architecture).zip"
        return Asset(name: name, browser_download_url: URL(string: "https://github.com/junli-nv/MyTerm/releases/download/\(tag)/\(name)")!, size: size, digest: nil)
    }
    public static func fallbackChecksum(tag: String) -> Asset {
        Asset(name: "SHA256SUMS.txt", browser_download_url: URL(string: "https://github.com/junli-nv/MyTerm/releases/download/\(tag)/SHA256SUMS.txt")!, size: 0, digest: nil)
    }
    public static let endpoint = URL(string: "https://api.github.com/repos/junli-nv/MyTerm/releases/latest")!
    public static let page = URL(string: "https://github.com/junli-nv/MyTerm/releases/latest")!

    public static func version(_ text: String) -> [Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    public func newer(than current: String) throws -> Bool {
        guard !draft, !prerelease, let remote = Self.version(tag_name), let local = Self.version(current) else {
            throw ConfigurationError.invalid("无法识别正式发布版本。")
        }
        return local.lexicographicallyPrecedes(remote)
    }
    public func installer(architecture: String) throws -> Asset {
        let version = tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        guard let asset = assets.first(where: { $0.name == "MyTerm-\(version)-macos-\(architecture).zip" }),
              asset.size > 0, asset.size <= 512 * 1024 * 1024, Self.trustedAssetURL(asset.browser_download_url) else {
            throw ConfigurationError.invalid("此版本没有兼容本机的更新安装包，请查看发布页面。")
        }
        return asset
    }
    public static func trustedAssetURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
        url.path.hasPrefix("/junli-nv/MyTerm/releases/download/") && url.query == nil && url.fragment == nil
    }
    public static func checksum(_ text: String, named name: String) throws -> String {
        let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { return nil }
            let filename = String(fields[1]).trimmingCharacters(in: .whitespaces)
            guard (filename.hasPrefix("*") ? String(filename.dropFirst()) : filename) == name else { return nil }
            return String(fields[0])
        }
        guard matches.count == 1, validDigest(matches[0]) else { throw ConfigurationError.invalid("更新安装包缺少有效的 SHA-256 校验值。") }
        return matches[0].lowercased()
    }
    public static func validDigest(_ text: String) -> Bool { text.count == 64 && text.allSatisfy { $0.isASCII && $0.isHexDigit } }
    public static func verify(_ file: URL, digest: String, size: Int64) throws {
        guard validDigest(digest), (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(size) else {
            throw ConfigurationError.invalid("更新安装包大小或校验值不正确。")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest.lowercased() else {
            throw ConfigurationError.invalid("更新安装包 SHA-256 校验失败；未安装。")
        }
    }
}
