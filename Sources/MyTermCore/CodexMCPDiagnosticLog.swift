import Foundation
import Darwin

/// Opt-in, bounded cross-process metadata. Never accepts protocol payloads or free-form errors.
public struct CodexMCPDiagnosticLog {
    public enum Event: String, Codable {
        case started, initializeReceived, initializeReplied, initialized, toolsListReceived, toolsListReplied
        case parseError, inputEOF, inputError, inputLimit, outputError
    }
    public struct Entry: Codable, Equatable {
        public let time: Date
        public let process: Int32
        public let parent: Int32
        public let event: Event
        public let errorNumber: Int32?
    }
    public struct Snapshot: Codable, Equatable {
        public var expires: Date?
        public var recording = false
        public var dropped = 0
        public var entries: [Entry] = []
    }
    public static let shared: CodexMCPDiagnosticLog = {
        if CommandLine.arguments.contains("--smoke-test"), let path = ProcessInfo.processInfo.environment["MYTERM_TEST_MCP_DIAGNOSTICS"] {
            return CodexMCPDiagnosticLog(url: URL(fileURLWithPath: path))
        }
        return CodexMCPDiagnosticLog(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyTerm/mcp-diagnostics.json"))
    }()
    private let url: URL
    public init(url: URL) { self.url = url }
    // flock protects concurrent adapters; nonblocking acquisition keeps diagnostics from delaying MCP.
    private func access(create: Bool = false, mutate: Bool = false, _ body: (inout Snapshot) -> Void) -> Snapshot {
        if create { try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        let fd = open(url.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC | (create ? O_CREAT : 0), 0o600)
        guard fd >= 0 else { return Snapshot() }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size <= 131072,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { return Snapshot() }
        defer { flock(fd, LOCK_UN) }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.isEmpty ? 0 : read(fd, &bytes, bytes.count)
        var snapshot = count == bytes.count ? ((try? JSONDecoder().decode(Snapshot.self, from: Data(bytes))) ?? Snapshot()) : Snapshot()
        let previous = snapshot
        body(&snapshot)
        if mutate, snapshot != previous, let data = try? JSONEncoder().encode(snapshot) {
            _ = lseek(fd, 0, SEEK_SET)
            let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written == data.count { _ = ftruncate(fd, off_t(data.count)) }
        }
        return snapshot
    }
    public func start(now: Date = Date()) { _ = access(create: true, mutate: true) { $0 = Snapshot(expires: now.addingTimeInterval(900), recording: true) } }
    public func stop() { _ = access(mutate: true) { $0.recording = false } }
    public func clear() { _ = access(mutate: true) { $0 = Snapshot() } }
    public func snapshot() -> Snapshot { access { if Date() >= ($0.expires ?? .distantPast) { $0.recording = false } } }
    public func record(_ event: Event, errorNumber: Int32? = nil, now: Date = Date()) {
        _ = access(mutate: true) { state in
            guard state.recording, now < (state.expires ?? .distantPast) else { return }
            state.entries.append(Entry(time: now, process: getpid(), parent: getppid(), event: event, errorNumber: errorNumber))
            if state.entries.count > 256 { state.entries.removeFirst(); state.dropped += 1 }
        }
    }
}
