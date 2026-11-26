import Foundation
import Darwin

private func canonicalTransferPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// Paths and policy are data, never interpolated into a remote shell command.
public struct CodexTransferRequest {
    public enum Conflict: String { case error, skip, overwrite }
    public enum Direction: String { case upload, download }
    public let direction: Direction
    public let sources: [URL]
    public let destination: String
    public let conflict: Conflict
    public let exclusions: [String]

    public init(arguments: [String: Any], direction: Direction = .upload) throws {
        self.direction = direction
        let pathsKey = direction == .upload ? "local_paths" : "remote_paths"
        let destinationKey = direction == .upload ? "remote_directory" : "local_directory"
        guard let paths = arguments[pathsKey] as? [String], (1...64).contains(paths.count),
              let rawDestination = arguments[destinationKey] as? String else {
            throw ConfigurationError.invalid("Provide 1–64 \(pathsKey) and \(destinationKey)")
        }
        let destination = direction == .download ? (rawDestination as NSString).expandingTildeInPath : rawDestination
        guard
              destination.hasPrefix("/"), destination.utf8.count <= 4096,
              !destination.split(separator: "/").contains(".."),
              !destination.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let conflict = Conflict(rawValue: arguments["conflict"] as? String ?? "error") else {
            throw ConfigurationError.invalid("Provide an absolute destination directory and conflict: error/skip/overwrite")
        }
        let exclusions = arguments["exclude"] as? [String] ?? []
        guard arguments["exclude"] == nil || arguments["exclude"] is [String], exclusions.count <= 64,
              exclusions.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && !$0.contains("\0") && !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
            throw ConfigurationError.invalid("exclude accepts up to 64 relative glob patterns (256 bytes each)")
        }
        sources = try paths.map { path in
            let expanded = direction == .upload ? (path as NSString).expandingTildeInPath : path
            guard expanded.hasPrefix("/"), expanded.utf8.count <= 4096,
                  !expanded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigurationError.invalid("Local paths must be absolute or start with ~/")
            }
            // Never standardize remote paths using the Mac's filesystem aliases.
            let url = direction == .download ? URL(fileURLWithPath: expanded) : URL(fileURLWithPath: expanded).standardizedFileURL
            guard url.path != "/" else { throw ConfigurationError.invalid("Select a file or directory, not the filesystem root") }
            if direction == .download {
                guard !expanded.split(separator: "/").contains("..") else { throw ConfigurationError.invalid("Remote paths must not contain ..") }
                return url
            }
            let parent = canonicalTransferPath(url.deletingLastPathComponent().path) ?? url.deletingLastPathComponent().path
            return URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent)
        }
        guard Set(sources.map(\.lastPathComponent)).count == sources.count else {
            throw ConfigurationError.invalid("Selected items have duplicate destination names")
        }
        self.destination = direction == .download ? (canonicalTransferPath(destination) ?? destination) : destination
        self.conflict = conflict; self.exclusions = exclusions
        guard summary.utf8.count <= 16_000 else { throw ConfigurationError.invalid("Transfer selection is too large; use fewer paths/patterns (16 KiB summary limit)") }
    }

    public var summary: String {
        direction.rawValue + "\n" + sources.map(\.path).joined(separator: "\n") + "\n→ " + destination + "\nconflict=" + conflict.rawValue
            + (exclusions.isEmpty ? "" : "\nexclude=" + exclusions.joined(separator: ", "))
    }
    public func excludes(_ relative: String) -> Bool {
        exclusions.contains { pattern in
            if pattern.contains("/") { return fnmatch(pattern, relative, FNM_PATHNAME) == 0 }
            return relative.split(separator: "/").contains { fnmatch(pattern, String($0), 0) == 0 }
        }
    }
    public static func sftpArguments(controlPath: String, host: String) -> [String] {
        ["-F", "/dev/null", "-T", "-S", controlPath, "-o", "ControlMaster=no",
         "-o", "ProxyCommand=/usr/bin/false", "-o", "BatchMode=yes", "-o", "PermitLocalCommand=no",
         "-o", "ClearAllForwardings=yes", "-o", "ConnectTimeout=5", "-s", "--", host, "sftp"]
    }
}

/// One worker owns SFTP; cancellation is the only concurrent client operation.
/// The bounded manifest is validated before any remote writes, including links.
public final class CodexTransferJob {
    private struct Item { let source: URL, target: String, directory: Bool, size: UInt64 }
    private let lock = NSLock()
    private let request: CodexTransferRequest
    private let client: SFTPClient
    private var cancelled = false
    private var state = "running", phase = "preflight", current = "", message = ""
    private var totalBytes: UInt64 = 0, processedBytes: UInt64 = 0, currentBytes: UInt64 = 0
    private var currentTotal: UInt64 = 0, transferredBytes: UInt64 = 0, resumedBytes: UInt64 = 0
    private var sawProgress = false
    private let started = ProcessInfo.processInfo.systemUptime
    private var totalItems = 0, completed = 0, skipped = 0, failed = 0
    private var failures = [[String: String]]()
    private let deadline: Date

    public init(request: CodexTransferRequest, arguments: [String], timeout: TimeInterval, resumeIdentity: String? = nil) {
        self.request = request; self.deadline = Date().addingTimeInterval(timeout)
        client = SFTPClient(arguments: arguments, resumeIdentity: resumeIdentity)
        DispatchQueue.global(qos: .utility).async { self.run() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let active = self.state == "running"; self.lock.unlock()
            if active { self.cancel() }
        }
    }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return state == "running" }
    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        client.cancel()
    }
    private func check() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped || Date() >= deadline { throw ConfigurationError.invalid("Transfer cancelled or authorization/transfer timeout expired; completed files remain, retry the same paths to resume") }
    }
    public func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["state": state, "phase": phase, "operation": request.direction.rawValue, "total_items": totalItems, "total_bytes": totalBytes,
                "processed_bytes": processedBytes, "completed_items": completed, "skipped_items": skipped,
                "progress_bytes": processedBytes + currentBytes, "transferred_bytes": transferredBytes,
                "resumed_bytes": resumedBytes, "average_bytes_per_second": Double(transferredBytes) / max(0.001, ProcessInfo.processInfo.systemUptime - started),
                "failed_items": failed, "failures": failures, "failures_truncated": failed > failures.count,
                "current_file": current, "current_file_bytes": currentBytes, "current_file_size": currentTotal, "error": message,
                "partial": state != "completed" && (completed > 0 || currentBytes > 0),
                "retry_guidance": "Retry the same paths and server configuration to resume matching partials; completed identical files are skipped. Source changes or identity mismatch require a new destination or explicit resolution."]
    }
    private func progress(_ bytes: UInt64, total: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if !sawProgress { resumedBytes += bytes; sawProgress = true }
        else if bytes >= currentBytes { transferredBytes += bytes - currentBytes }
        currentBytes = bytes; currentTotal = total
    }
    private func manifest() throws -> [Item] {
        var result = [Item]()
        func visit(_ url: URL, relative: String, target: String, depth: Int) throws {
            try check()
            guard depth <= 128, result.count < 100_000 else { throw ConfigurationError.invalid("Upload exceeds 128 directory levels or 100000 items") }
            if request.excludes(relative) { return }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true,
                  canonicalTransferPath(url.path) == url.path else {
                throw ConfigurationError.invalid("Upload does not follow symbolic links or special files: " + url.path)
            }
            let directory = values.isDirectory == true
            result.append(Item(source: url, target: target, directory: directory, size: directory ? 0 : UInt64(max(0, values.fileSize ?? 0))))
            if directory {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent,
                              target: SFTPClient.joining(target, child.lastPathComponent), depth: depth + 1)
                }
            }
        }
        for source in request.sources {
            try visit(source, relative: source.lastPathComponent,
                      target: SFTPClient.joining(request.destination, source.lastPathComponent), depth: 0)
        }
        return result
    }
    private func checkRemoteParents(_ path: String) throws {
        var parent = ""
        for part in path.split(separator: "/").dropLast() {
            parent += "/" + part
            guard let entry = try client.attributes(at: parent), entry.isDirectory, !entry.isLink else {
                throw ConfigurationError.invalid("Remote parent must be an existing directory, not a link: " + parent)
            }
        }
    }
    private func downloadManifest() throws -> [Item] {
        let destination = URL(fileURLWithPath: request.destination)
        guard canonicalTransferPath(destination.path) == destination.path,
              try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ConfigurationError.invalid("Local destination must be an existing directory")
        }
        var result = [Item]()
        func visit(_ remote: String, local: URL, relative: String, depth: Int) throws {
            try check()
            if request.excludes(relative) { return }
            guard depth <= 128, result.count < 100_000 else { throw ConfigurationError.invalid("Transfer exceeds 128 directory levels or 100000 items") }
            guard let entry = try client.attributes(at: remote), !entry.isLink, entry.isDirectory || entry.isRegularFile else {
                throw ConfigurationError.invalid("Download does not follow links or special files: " + remote)
            }
            result.append(Item(source: local, target: remote, directory: entry.isDirectory, size: entry.isDirectory ? 0 : entry.size ?? 0))
            if entry.isDirectory {
                for child in try client.list(remote) {
                    // Never let a malicious server escape the selected local tree.
                    guard ![".", ".."].contains(child.name), !child.name.isEmpty,
                          !child.name.contains("/"), !child.name.contains("\0") else { throw ConfigurationError.invalid("Invalid remote directory entry") }
                    try visit(SFTPClient.joining(remote, child.name), local: local.appendingPathComponent(child.name),
                              relative: relative + "/" + child.name, depth: depth + 1)
                }
            }
        }
        for source in request.sources {
            try checkRemoteParents(source.path)
            try visit(source.path, local: destination.appendingPathComponent(source.lastPathComponent), relative: source.lastPathComponent, depth: 0)
        }
        return result
    }
    /// Returns true only when a completed local file was skipped.
    private func download(_ item: Item) throws -> Bool {
        try checkRemoteParents(item.target)
        let local = item.source, parent = local.deletingLastPathComponent().path
        guard canonicalTransferPath(parent) == parent else { throw ConfigurationError.invalid("Local parent changed or contains a symbolic link") }
        let fm = FileManager.default
        let attributes: [FileAttributeKey: Any]?
        do { attributes = try fm.attributesOfItem(atPath: local.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { attributes = nil }
        let type = attributes?[.type] as? FileAttributeType
        if item.directory {
            if attributes != nil {
                guard type == .typeDirectory else { throw ConfigurationError.invalid("Local directory conflicts with a file or link") }
            } else { try fm.createDirectory(at: local, withIntermediateDirectories: false) }
        } else {
            guard let remote = try client.attributes(at: item.target), remote.isRegularFile, !remote.isLink else { throw ConfigurationError.invalid("Remote source changed type") }
            if attributes != nil {
                guard type == .typeRegular else { throw ConfigurationError.invalid("Local destination is not a regular file") }
                if request.conflict == .skip { return true }
                if try client.contentsMatch(local, remote: item.target) { return true }
                guard request.conflict == .overwrite else { throw ConfigurationError.invalid("Local file exists; choose skip or overwrite") }
            }
            try client.download(item.target, to: local) { self.progress($0, total: $1) }
        }
        return false
    }
    private func run() {
        defer { client.close() }
        do {
            let items: [Item]
            if request.direction == .upload {
                items = try manifest()
                lock.lock(); phase = "connecting"; lock.unlock()
                try check(); try client.connect()
            } else {
                lock.lock(); phase = "connecting"; lock.unlock()
                try check(); try client.connect()
                lock.lock(); phase = "preflight"; lock.unlock()
                items = try downloadManifest()
            }
            var bytes: UInt64 = 0
            for item in items {
                let sum = bytes.addingReportingOverflow(item.size)
                guard !sum.overflow else { throw ConfigurationError.invalid("Transfer byte count exceeds supported range") }
                bytes = sum.partialValue
            }
            lock.lock(); totalItems = items.count; totalBytes = bytes; phase = "transferring"; lock.unlock()
            var blocked = Set<String>()
            for item in items {
                try check()
                lock.lock(); current = request.direction == .upload ? item.source.path : item.target
                currentBytes = 0; currentTotal = item.size; sawProgress = false; lock.unlock()
                do {
                    var parent = (item.target as NSString).deletingLastPathComponent
                    while parent != "/" && !parent.isEmpty {
                        guard !blocked.contains(parent) else { throw ConfigurationError.invalid("Parent directory could not be transferred") }
                        parent = (parent as NSString).deletingLastPathComponent
                    }
                    if request.direction == .download {
                        if try download(item) {
                            lock.lock(); skipped += 1; processedBytes += item.size; lock.unlock()
                            continue
                        }
                        lock.lock(); completed += 1; processedBytes += item.size; currentBytes = 0; lock.unlock()
                        continue
                    }
                    // Revalidate local links after preflight, immediately before each operation.
                    guard canonicalTransferPath(item.source.path) == item.source.path else {
                        throw ConfigurationError.invalid("Local path changed to a symbolic link")
                    }
                    try checkRemoteParents(item.target)
                    let existing = try client.attributes(at: item.target)
                    if item.directory {
                        if let existing {
                            guard existing.isDirectory, !existing.isLink else { throw ConfigurationError.invalid("Remote directory conflicts with a file or link") }
                        } else { try client.createDirectory(item.target) }
                    } else {
                        if let existing {
                            guard existing.isRegularFile, !existing.isLink else { throw ConfigurationError.invalid("Remote target is not a regular file") }
                            if request.conflict == .skip {
                                lock.lock(); skipped += 1; processedBytes += item.size; lock.unlock()
                                continue
                            }
                            // Identical completed files are safe to skip when retrying a directory.
                            if try client.contentsMatch(item.source, remote: item.target) {
                                lock.lock(); skipped += 1; processedBytes += item.size; lock.unlock()
                                continue
                            }
                            guard request.conflict == .overwrite else { throw ConfigurationError.invalid("Remote file exists; choose skip or overwrite") }
                        }
                        try client.upload(item.source, to: item.target, overwrite: request.conflict == .overwrite) { self.progress($0, total: $1) }
                    }
                    lock.lock(); completed += 1; processedBytes += item.size; currentBytes = 0; lock.unlock()
                } catch {
                    try check()
                    if item.directory { blocked.insert(item.target) }
                    lock.lock(); failed += 1
                    if failures.count < 50 {
                        let failure = ["local_path": item.source.path, "remote_path": item.target, "error": String(error.localizedDescription.prefix(1024))]
                        let proposed = failures + [failure]
                        if let data = try? JSONSerialization.data(withJSONObject: proposed), data.count <= 8192 { failures = proposed }
                    }
                    lock.unlock()
                }
            }
            try check()
            lock.lock(); state = failed == 0 ? "completed" : "failed"; phase = state; current = ""; lock.unlock()
        } catch {
            lock.lock(); state = cancelled || Date() >= deadline ? "cancelled" : "failed"; phase = state; message = error.localizedDescription; lock.unlock()
        }
    }
}
