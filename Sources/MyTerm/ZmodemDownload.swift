import AppKit
import CryptoKit
import MyTermCore

/// Receive into a private, locked staging directory. Existing user files are only
/// replaced after successful reception and a conflict decision, never by lrz.
final class ZmodemDownload {
    let directory: URL
    private let destination: URL
    private var lock: Int32 = -1
    init(destination: URL, identity: String, storage: URL? = nil) throws {
        self.destination = destination
        let digest = SHA256.hash(data: Data((identity + "\0" + destination.standardizedFileURL.path).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let base = (storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyTerm/ZmodemPartial")).appendingPathComponent(digest)
        directory = base.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lock = open(base.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { close(lock); lock = -1 }
            throw ConfigurationError.invalid("此目录已有 ZMODEM 下载，请等待完成。")
        }
    }
    /// lrz's stricter -R mode forbids resume. Keep its normal path checks and
    /// additionally confine all writes to staging, including hostile filenames.
    func configureReceiver(_ process: Process, executable: String) throws {
        guard let resolved = realpath(directory.path, nil) else { throw POSIXError(.ENOENT) }
        let path = String(cString: resolved)
        free(resolved)
        let quoted = String(decoding: try JSONSerialization.data(withJSONObject: path, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        let profile = "(version 1)(allow default)(deny network*)(deny file-write* (require-not (subpath " + quoted + ")))"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", profile, executable, "--binary", "--escape", "--resume"]
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { process.arguments?.append("-vv") }
    }
    deinit { if lock >= 0 { flock(lock, LOCK_UN); close(lock) } }
    var hasPartialFiles: Bool { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty == false }
    func restart() throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
    // Called on the transfer worker; conflict UI is marshalled to the main run loop.
    func finish(conflicts: TransferConflict) throws {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path })
        guard !files.isEmpty else { throw ConfigurationError.invalid("ZMODEM 未收到文件。") }
        for file in files {
            try conflicts.checkActive()
            let sourceType = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard sourceType.isRegularFile == true, sourceType.isSymbolicLink != true else {
                throw ConfigurationError.invalid("ZMODEM 仅支持普通文件，请使用 SFTP 下载目录。")
            }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if let type = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                guard try conflicts.resolve(file, target: target.path, canReplace: type.isRegularFile == true && type.isSymbolicLink != true) else {
                    try fm.removeItem(at: file); continue
                }
                guard type.isRegularFile == true, type.isSymbolicLink != true else { throw CancellationError() }
            }
            // Same-directory temporary copy makes the final rename atomic even on another volume.
            let temporary = destination.appendingPathComponent(".myterm-zmodem-" + UUID().uuidString)
            defer { try? fm.removeItem(at: temporary) }
            try fm.copyItem(at: file, to: temporary)
            try conflicts.checkActive()
            guard Darwin.rename(temporary.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try fm.removeItem(at: file)
        }
    }
}
