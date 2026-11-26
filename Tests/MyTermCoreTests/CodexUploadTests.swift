import Foundation
import MyTermCore

func checkCodexUploads() throws {
    let arguments: [String: Any] = ["local_paths": ["/tmp/kb"], "remote_directory": "/data", "exclude": [".git", "*.pyc", "kb/cache/*"]]
    let request = try CodexTransferRequest(arguments: arguments)
    for path in ["kb/.git/config", "kb/a/b.pyc", "kb/cache/file"] { checkEqual(request.excludes(path), true) }
    for path in ["kb/.gitignore", "kb/src/file", "kb/cache/sub/file"] { checkEqual(request.excludes(path), false) }
    for changes: [String: Any] in [["local_paths": []], ["local_paths": ["relative"]], ["local_paths": ["/"]],
        ["local_paths": ["/a/kb", "/b/kb"]], ["remote_directory": "~/data"], ["remote_directory": "/data/../secret"],
        ["remote_directory": "/bad\npath"], ["exclude": "*.pyc"], ["exclude": ["../private"]], ["conflict": "replace_all"]] {
        checkThrows(try CodexTransferRequest(arguments: arguments.merging(changes) { _, new in new }))
    }
    let transport = CodexTransferRequest.sftpArguments(controlPath: "/tmp/control", host: "unreachable.invalid")
    checkEqual(transport.contains("ProxyCommand=/usr/bin/false"), true)
    checkEqual(transport.suffix(3), ["--", "unreachable.invalid", "sftp"])
    let launch = try CodexConnection.launchArguments(appExecutable: "/app/MyTerm")
    for tool in ["upload_items", "download_items", "transfer_status", "cancel_transfer"] {
        checkEqual(CodexMCP.tools.contains { $0["name"] as? String == tool }, true)
        checkEqual(launch.contains("mcp_servers.myterm.tools.\(tool).approval_mode=\"approve\""), true)
        checkEqual(launch.contains { $0.hasPrefix("mcp_servers.myterm.enabled_tools=") && $0.contains(tool) }, true)
    }
}

/// Production SFTP over a real, authenticated mux; invoked by the SSH fixture.
func runCodexUploadFixture(control: String, root: URL) throws {
    let fm = FileManager.default
    let source = root.appendingPathComponent("upload-source/kb")
    let target = root.appendingPathComponent("upload-target")
    try fm.createDirectory(at: source.appendingPathComponent("子目录/empty"), withIntermediateDirectories: true)
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("hello 中文".utf8).write(to: source.appendingPathComponent("子目录/a ' $().txt"))
    try Data("hidden".utf8).write(to: source.appendingPathComponent(".hidden"))
    try Data("omit".utf8).write(to: source.appendingPathComponent("cache.pyc"))
    let extra = root.appendingPathComponent("extra.txt")
    try Data("extra".utf8).write(to: extra)
    func run(_ conflict: String = "error", paths: [String]? = nil, remote: String? = nil) throws -> [String: Any] {
        let request = try CodexTransferRequest(arguments: ["local_paths": paths ?? [source.path, extra.path],
            "remote_directory": remote ?? target.path, "exclude": ["*.pyc"], "conflict": conflict])
        let job = CodexTransferJob(request: request,
            arguments: CodexTransferRequest.sftpArguments(controlPath: control, host: "127.0.0.1"), timeout: 10)
        let deadline = Date().addingTimeInterval(12)
        while job.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        checkEqual(job.isRunning, false)
        return job.snapshot()
    }
    let initial = try run()
    if initial["state"] as? String != "completed" { print(initial) }
    checkEqual(initial["state"] as? String, "completed")
    let uploaded = target.appendingPathComponent("kb/子目录/a ' $().txt")
    checkEqual(try Data(contentsOf: uploaded), Data("hello 中文".utf8))
    checkEqual(fm.fileExists(atPath: target.appendingPathComponent("kb/子目录/empty").path), true)
    checkEqual(fm.fileExists(atPath: target.appendingPathComponent("kb/.hidden").path), true)
    checkEqual(fm.fileExists(atPath: target.appendingPathComponent("kb/cache.pyc").path), false)
    try Data("remote only".utf8).write(to: target.appendingPathComponent("kb/remote-only"))
    checkEqual(try run()["state"] as? String, "completed")
    try Data("changed".utf8).write(to: source.appendingPathComponent("子目录/a ' $().txt"))
    let conflict = try run()
    checkEqual(conflict["state"] as? String, "failed")
    checkEqual(conflict["failed_items"] as? Int, 1)
    checkEqual(try Data(contentsOf: uploaded), Data("hello 中文".utf8))
    checkEqual(try run("skip")["state"] as? String, "completed")
    checkEqual(try Data(contentsOf: uploaded), Data("hello 中文".utf8))
    checkEqual(try run("overwrite")["state"] as? String, "completed")
    checkEqual(try Data(contentsOf: uploaded), Data("changed".utf8))
    checkEqual(fm.fileExists(atPath: target.appendingPathComponent("kb/remote-only").path), true)
    let downloadDirectory = root.appendingPathComponent("downloads")
    try fm.createDirectory(at: downloadDirectory, withIntermediateDirectories: false)
    let transport = CodexTransferRequest.sftpArguments(controlPath: control, host: "127.0.0.1")
    func wait(_ job: CodexTransferJob) -> [String: Any] {
        let limit = Date().addingTimeInterval(15)
        while job.isRunning && Date() < limit { Thread.sleep(forTimeInterval: 0.001) }
        checkEqual(job.isRunning, false)
        return job.snapshot()
    }
    func download(_ policy: String = "error") throws -> [String: Any] {
        let request = try CodexTransferRequest(arguments: ["remote_paths": [target.appendingPathComponent("kb").path, target.appendingPathComponent("extra.txt").path],
            "local_directory": downloadDirectory.path, "exclude": ["remote-only"], "conflict": policy], direction: .download)
        return wait(CodexTransferJob(request: request, arguments: transport, timeout: 12, resumeIdentity: "fixture-server"))
    }
    let downloaded = downloadDirectory.appendingPathComponent("kb/子目录/a ' $().txt")
    let firstDownload = try download()
    if firstDownload["state"] as? String != "completed" { print(firstDownload) }
    checkEqual(firstDownload["state"] as? String, "completed")
    checkEqual(try Data(contentsOf: downloaded), Data("changed".utf8))
    try fm.removeItem(at: downloaded)
    try fm.createSymbolicLink(at: downloaded, withDestinationURL: extra)
    checkEqual(try download("overwrite")["state"] as? String, "failed")
    checkEqual(try Data(contentsOf: extra), Data("extra".utf8))
    try fm.removeItem(at: downloaded)
    checkEqual(try download()["state"] as? String, "completed")
    checkEqual(fm.fileExists(atPath: downloadDirectory.appendingPathComponent("kb/子目录/empty").path), true)
    checkEqual(fm.fileExists(atPath: downloadDirectory.appendingPathComponent("kb/.hidden").path), true)
    checkEqual(fm.fileExists(atPath: downloadDirectory.appendingPathComponent("kb/remote-only").path), false)
    try Data("local edit".utf8).write(to: downloaded)
    checkEqual(try download()["state"] as? String, "failed")
    checkEqual(try download("skip")["state"] as? String, "completed")
    checkEqual(try Data(contentsOf: downloaded), Data("local edit".utf8))
    checkEqual(try download("overwrite")["state"] as? String, "completed")
    checkEqual(try Data(contentsOf: downloaded), Data("changed".utf8))
    // Observe actual progress, cancel while bytes are moving, then resume in a new job.
    let large = root.appendingPathComponent("large.bin")
    try Data(repeating: 0x61, count: 16 * 1024 * 1024).write(to: large)
    for direction in [CodexTransferRequest.Direction.upload, .download] {
        let request = try CodexTransferRequest(arguments: direction == .upload
            ? ["local_paths": [large.path], "remote_directory": target.path]
            : ["remote_paths": [target.appendingPathComponent("large.bin").path], "local_directory": downloadDirectory.path], direction: direction)
        let interrupted = CodexTransferJob(request: request, arguments: transport, timeout: 12, resumeIdentity: "stable-server")
        var sawProgress = false
        let limit = Date().addingTimeInterval(12)
        while interrupted.isRunning && Date() < limit {
            let progress = interrupted.snapshot(), bytes = progress["current_file_bytes"] as? UInt64 ?? 0
            if bytes > 0 && bytes < 16 * 1024 * 1024 {
                checkEqual((progress["progress_bytes"] as? UInt64 ?? 0) >= bytes, true)
                sawProgress = true; interrupted.cancel(); break
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        checkEqual(sawProgress, true)
        checkEqual(wait(interrupted)["state"] as? String, "cancelled")
        let resumed = wait(CodexTransferJob(request: request, arguments: ["-o", "LogLevel=ERROR"] + transport, timeout: 12, resumeIdentity: "stable-server"))
        if resumed["state"] as? String != "completed" { print(resumed) }
        checkEqual(resumed["state"] as? String, "completed")
        checkGreaterThan(resumed["resumed_bytes"] as? UInt64 ?? 0, 0)
    }
    checkEqual(try Data(contentsOf: downloadDirectory.appendingPathComponent("large.bin")), try Data(contentsOf: large))
    // Preflight rejects a link before uploading any of the selection.
    try fm.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: extra)
    checkEqual(try run()["state"] as? String, "failed")
    try fm.removeItem(at: source.appendingPathComponent("link"))
    let remoteLink = root.appendingPathComponent("remote-link")
    try fm.createSymbolicLink(at: remoteLink, withDestinationURL: target)
    checkEqual(try run(remote: remoteLink.path)["state"] as? String, "failed")
    let linkRequest = try CodexTransferRequest(arguments: ["remote_paths": [remoteLink.path], "local_directory": downloadDirectory.path], direction: .download)
    checkEqual(wait(CodexTransferJob(request: linkRequest, arguments: transport, timeout: 5))["state"] as? String, "failed")
    // No mux means no fallback login, even when the host happens to be reachable.
    let disconnected = CodexTransferJob(request: try CodexTransferRequest(arguments: ["local_paths": [extra.path], "remote_directory": target.path]),
        arguments: CodexTransferRequest.sftpArguments(controlPath: root.appendingPathComponent("missing-socket").path, host: "127.0.0.1"), timeout: 2)
    while disconnected.isRunning { Thread.sleep(forTimeInterval: 0.01) }
    checkEqual(disconnected.snapshot()["state"] as? String, "failed")
    print("PASS: Codex SFTP upload/download: multi-file/directories, Unicode, empty/hidden directories, filters, conflicts, live progress, cancellation/resume, local/remote links and mux-only transport")
}
