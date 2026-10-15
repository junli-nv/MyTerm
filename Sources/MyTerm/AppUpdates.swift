import AppKit
import SwiftUI
import MyTermCore

final class AppUpdateModel: ObservableObject {
    @Published var status = "点击检查 GitHub 上的最新正式版。"
    @Published var release: AppRelease?
    @Published var busy = false
    @Published var available = false
    private var task: Task<Void, Never>?
    private var staging: URL?
    let current: String
    private let network: URLSession
    init(current: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0",
         network: URLSession = URLSession(configuration: .ephemeral)) {
        self.current = current; self.network = network
    }
    func cancel() { task?.cancel() }

    func check() {
        guard !busy else { return }
        busy = true; available = false; release = nil; status = "正在检查更新…"
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await fetchLatest()
                available = try result.newer(than: current)
                release = result
                status = available ? "发现新版本。" : "当前版本已是最新，或高于 GitHub 正式版。"
            } catch { status = Task.isCancelled ? "更新操作已取消。" : L10n.text("检查更新失败：") + L10n.text(error.localizedDescription) }
        }
    }

    func install() {
        guard !busy, available, let release else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("安装更新并重新启动？")
        alert.informativeText = L10n.text("当前终端会话将结束，请先保存工作。更新会保留设置和已保存的会话配置。")
        alert.addButton(withTitle: L10n.text("下载并安装")); alert.addButton(withTitle: L10n.text("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true; status = "正在下载更新…"
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
                guard target.lastPathComponent == "MyTerm.app", FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path),
                      (try target.resourceValues(forKeys: [.volumeIsReadOnlyKey])).volumeIsReadOnly != true else {
                    throw ConfigurationError.invalid("当前应用位置不可更新，请将 MyTerm 安装到可写的 Applications 文件夹后重试。")
                }
                #if arch(arm64)
                let architecture = "arm64"
                #else
                let architecture = "x86_64"
                #endif
                let asset = try release.installer(architecture: architecture)
                let digest: String
                if let raw = asset.digest, raw.hasPrefix("sha256:"), AppRelease.validDigest(String(raw.dropFirst(7))) {
                    digest = String(raw.dropFirst(7))
                } else {
                    guard let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }), AppRelease.trustedAssetURL(sums.browser_download_url) else {
                        throw ConfigurationError.invalid("更新安装包缺少有效的 SHA-256 校验值。")
                    }
                    digest = try AppRelease.checksum(String(decoding: await fetch(sums.browser_download_url), as: UTF8.self), named: asset.name)
                }
                let (download, response) = try await network.download(for: request(asset.browser_download_url))
                defer { try? FileManager.default.removeItem(at: download) }
                try validate(response)
                try Task.checkCancellation()
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("myterm-update-\(UUID())")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                staging = root
                let archive = root.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: download, to: archive)
                status = "正在校验并准备安装…"
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                let identifier = Bundle.main.bundleIdentifier ?? ""
                let prepared = try await Task.detached {
                    try AppRelease.verify(archive, digest: digest, size: asset.size)
                    return try AppUpdatePreparation.prepare(root: root, version: version, identifier: identifier, architecture: architecture)
                }.value
                try Task.checkCancellation()
                guard let bundledHelper = Bundle.main.url(forResource: "install-update", withExtension: "sh") else {
                    throw ConfigurationError.invalid("更新组件缺失，请重新安装 MyTerm。")
                }
                let helper = root.appendingPathComponent("install.sh")
                try FileManager.default.copyItem(at: bundledHelper, to: helper)
                let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MyTerm")
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let log = logs.appendingPathComponent("Update.log")
                FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
                let output = try FileHandle(forWritingTo: log)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), prepared.path, target.path, version, root.path]
                process.environment = ProcessInfo.processInfo.environment.filter {
                    !["BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS"].contains($0.key) && !$0.key.hasPrefix("BASH_FUNC_")
                }
                process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
                try process.run(); try? output.close()
                do {
                    let ready = root.appendingPathComponent("ready")
                    let deadline = Date().addingTimeInterval(5)
                    while !FileManager.default.fileExists(atPath: ready.path) && process.isRunning && Date() < deadline {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    try Task.checkCancellation()
                    guard process.isRunning, FileManager.default.fileExists(atPath: ready.path) else {
                        throw ConfigurationError.invalid("更新安装进程未准备就绪；当前应用将保持运行。")
                    }
                } catch {
                    if process.isRunning { process.terminate() }
                    throw error
                }
                staging = nil // The independent helper now owns cleanup and rollback.
                NSApp.terminate(nil)
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging); self.staging = nil }
                status = Task.isCancelled ? "更新操作已取消。" : L10n.text("更新失败，当前应用未替换：") + L10n.text(error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> AppRelease {
        let (data, response) = try await network.data(for: request(AppRelease.endpoint))
        if let http = response as? HTTPURLResponse, [403, 429].contains(http.statusCode) {
            // The public latest-release redirect is independent of GitHub's API quota.
            // Derive only our known artifact names; never scrape executable links from HTML.
            var pageRequest = request(AppRelease.page); pageRequest.httpMethod = "HEAD"
            let (_, page) = try await network.data(for: pageRequest)
            try validate(page)
            guard let url = page.url else { throw ConfigurationError.invalid("无法识别正式发布版本。") }
            let tag = try AppRelease.latestPageTag(url)
            let notes = L10n.text("GitHub API 暂不可用，已通过公开发布页检查。完整更新说明请点击“发布页面”。")
            let result = AppRelease(tag: tag, notes: notes, assets: [])
            guard try result.newer(than: current) else { return result }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            let candidate = AppRelease.fallbackAsset(tag: tag, architecture: architecture, size: 0)
            var assetRequest = request(candidate.browser_download_url); assetRequest.httpMethod = "HEAD"
            let (_, assetResponse) = try await network.data(for: assetRequest)
            try validate(assetResponse)
            let asset = AppRelease.fallbackAsset(tag: tag, architecture: architecture, size: assetResponse.expectedContentLength)
            let fallback = AppRelease(tag: tag, notes: notes, assets: [asset, AppRelease.fallbackChecksum(tag: tag)])
            _ = try fallback.installer(architecture: architecture)
            return fallback
        }
        try validate(response)
        guard data.count <= 2 * 1024 * 1024 else { throw ConfigurationError.invalid("更新信息过大，已停止处理。") }
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("MyTerm/\(current)", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return request
    }
    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else {
            throw ConfigurationError.invalid(L10n.text("GitHub 请求失败，HTTP 状态：") + String((response as? HTTPURLResponse)?.statusCode ?? 0))
        }
    }
    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await network.data(for: request(url))
        try validate(response)
        guard data.count <= 2 * 1024 * 1024 else { throw ConfigurationError.invalid("更新信息过大，已停止处理。") }
        return data
    }
}

/// Slow validation runs off the UI thread. No downloaded program is executed here.
enum AppUpdatePreparation {
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ConfigurationError.invalid("更新安装包验证失败；当前应用未替换。") }
    }
    static func prepare(root: URL, version: String, identifier: String, architecture: String) throws -> URL {
        let unpacked = root.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", root.appendingPathComponent("update.zip").path, unpacked.path])
        let app = unpacked.appendingPathComponent("MyTerm.app")
        guard app.resolvingSymlinksInPath().path == app.standardizedFileURL.path,
              let bundle = Bundle(url: app), bundle.bundleIdentifier == identifier,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version else {
            throw ConfigurationError.invalid("更新安装包的应用标识或版本不匹配。")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let cpu = architecture == "arm64" ? NSBundleExecutableArchitectureARM64 : NSBundleExecutableArchitectureX86_64
        guard Bundle(url: app)?.executableArchitectures?.contains(NSNumber(value: cpu)) == true else {
            throw ConfigurationError.invalid("此版本没有兼容本机的更新安装包，请查看发布页面。")
        }
        return app
    }
}

final class AppUpdateController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = AppUpdateModel()
    func windowWillClose(_ notification: Notification) { model.cancel() }
    func present() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = L10n.text("检查更新")
        window.minSize = NSSize(width: 480, height: 340)
        window.contentView = NSHostingView(rootView: AppUpdateView(model: model))
        self.window = window
        window.center(); window.makeKeyAndOrderFront(nil)
        model.check()
    }
}

private struct AppUpdateView: View {
    @ObservedObject var model: AppUpdateModel
    @ObservedObject private var language = LanguagePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MyTerm \(model.current)").font(.title2)
            Text(L10n.text(model.status)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if model.busy { ProgressView().controlSize(.small) }
            if let release = model.release {
                Text(release.tag_name).font(.headline)
                ScrollView { Text(release.body ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else { Spacer() }
            HStack {
                if model.busy { Button(L10n.text("取消")) { model.cancel() } }
                Button(L10n.text("发布页面")) { NSWorkspace.shared.open(AppRelease.page) }
                Spacer()
                Button(L10n.text("检查更新")) { model.check() }.disabled(model.busy)
                Button(L10n.text("下载并安装")) { model.install() }.disabled(model.busy || !model.available)
            }
        }.padding(20).frame(minWidth: 440, minHeight: 300).environment(\.locale, language.locale)
    }
}
