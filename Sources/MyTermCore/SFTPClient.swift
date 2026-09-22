import Foundation
import Darwin
import CryptoKit

public struct RemoteEntry: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let size: UInt64?
    public let modified: UInt32?
    public let permissions: UInt32?
    public var isDirectory: Bool { (permissions ?? 0) & 0o170000 == 0o040000 }
    public var isLink: Bool { (permissions ?? 0) & 0o170000 == 0o120000 }
}

public struct SFTPError: LocalizedError {
    public let code: UInt32
    public let message: String
    public var errorDescription: String? { message }
}

private struct Wire {
    var data = Data()
    var offset = 0
    init(_ data: Data = Data()) { self.data = data }
    mutating func put(_ number: UInt32) { var value = number.bigEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
    mutating func put64(_ number: UInt64) { put(UInt32(number >> 32)); put(UInt32(truncatingIfNeeded: number)) }
    mutating func bytes(_ value: Data) { put(UInt32(value.count)); data.append(value) }
    mutating func string(_ value: String) { bytes(Data(value.utf8)) }
    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw SFTPError(code: 5, message: "SFTP 响应不完整。") }
        defer { offset += count }; return data.subdata(in: offset..<offset + count)
    }
    mutating func byte() throws -> UInt8 { try take(1)[0] }
    mutating func uint() throws -> UInt32 { try take(4).reduce(0) { ($0 << 8) | UInt32($1) } }
    mutating func uint64() throws -> UInt64 { let high = try uint(); return (UInt64(high) << 32) | UInt64(try uint()) }
    mutating func bytes() throws -> Data { try take(Int(uint())) }
    mutating func string() throws -> String {
        let value = try bytes()
        guard let string = String(data: value, encoding: .utf8) else { throw SFTPError(code: 5, message: "远端文件名不是 UTF-8 编码。") }
        return string
    }
    mutating func attributes(name: String = "") throws -> RemoteEntry {
        let flags = try uint()
        guard flags & ~UInt32(0x8000000f) == 0 else { throw SFTPError(code: 5, message: "不支持的 SFTP 属性。") }
        let size = flags & 1 != 0 ? try uint64() : nil
        if flags & 2 != 0 { _ = try uint(); _ = try uint() }
        let permissions = flags & 4 != 0 ? try uint() : nil
        var modified: UInt32?
        if flags & 8 != 0 { _ = try uint(); modified = try uint() }
        if flags & 0x80000000 != 0 {
            let count = try uint()
            guard count <= 1024 else { throw SFTPError(code: 5, message: "SFTP 扩展属性过多。") }
            for _ in 0..<count { _ = try bytes(); _ = try bytes() }
        }
        return RemoteEntry(name: name, size: size, modified: modified, permissions: permissions)
    }
}

/// Serial SFTP v3 client. Every operation runs off the UI thread. cancel() is thread-safe.
public final class SFTPClient {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var cancelled = false
    private var diagnostics = Data()
    private var requestID: UInt32 = 0
    private let resumeIdentity: String
    public init(executable: String = "/usr/bin/ssh", arguments: [String], resumeIdentity: String? = nil) {
        self.resumeIdentity = resumeIdentity ?? ([executable] + arguments).joined(separator: "\0")
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    }
    public func connect() throws {
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.lock.lock(); self.diagnostics.append(data)
            if self.diagnostics.count > 8192 { self.diagnostics = self.diagnostics.suffix(8192) }
            self.lock.unlock()
        }
        try process.run()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        for fd in [input.fileHandleForWriting.fileDescriptor, output.fileHandleForReading.fileDescriptor] {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }
        var hello = Wire(); hello.put(3)
        try send(type: 1, data: hello.data)
        var response = try receive()
        guard try response.byte() == 2, try response.uint() == 3 else { throw SFTPError(code: 5, message: "服务器未提供 SFTP v3。") }
    }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func close() {
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }
    deinit { close() }
    private func checkCancelled() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw SFTPError(code: 100, message: "传输已取消。再次选择同一文件和路径可继续传输。") }
    }
    private func waitReady(_ fd: Int32, events: Int16, deadline: Date) throws {
        while true {
            try checkCancelled()
            if Date() > deadline { throw SFTPError(code: 100, message: "SFTP 响应超时，临时文件已保留。") }
            var pollFD = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&pollFD, 1, 100)
            if result > 0 { return }
            if result < 0 && errno != EINTR { throw disconnected() }
        }
    }
    private func disconnected() -> SFTPError {
        lock.lock(); let log = String(decoding: diagnostics, as: UTF8.self); lock.unlock()
        return SFTPError(code: 7, message: "SFTP 连接已断开。请先在终端完成 SSH 登录，再连接 SFTP。\n\(log)")
    }
    private func read(_ count: Int, deadline: Date) throws -> Data {
        var result = Data()
        let fd = output.fileHandleForReading.fileDescriptor
        while result.count < count {
            try waitReady(fd, events: Int16(POLLIN), deadline: deadline)
            var buffer = [UInt8](repeating: 0, count: min(32768, count - result.count))
            let size = Darwin.read(fd, &buffer, buffer.count)
            if size > 0 { result.append(contentsOf: buffer.prefix(size)) }
            else if size == 0 || (errno != EAGAIN && errno != EINTR) { throw disconnected() }
        }
        return result
    }
    private func send(type: UInt8, data: Data) throws {
        var packet = Wire(); packet.put(UInt32(data.count + 1)); packet.data.append(type); packet.data.append(data)
        let deadline = Date().addingTimeInterval(30), fd = input.fileHandleForWriting.fileDescriptor
        // Suppress SIGPIPE for this descriptor instead of changing process-wide signal behavior.
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        var offset = 0
        while offset < packet.data.count {
            try waitReady(fd, events: Int16(POLLOUT), deadline: deadline)
            let count = packet.data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), min(4096, packet.data.count - offset)) }
            if count > 0 { offset += count }
            else if count == 0 || (errno != EAGAIN && errno != EINTR) { throw disconnected() }
        }
    }
    private func receive() throws -> Wire {
        let deadline = Date().addingTimeInterval(30)
        var header = Wire(try read(4, deadline: deadline)); let length = try header.uint()
        guard length >= 1 && length <= 4 * 1024 * 1024 else { throw SFTPError(code: 5, message: "SFTP 数据包大小无效。") }
        return Wire(try read(Int(length), deadline: deadline))
    }
    private func request(_ type: UInt8, _ payload: Wire, expecting: UInt8) throws -> Wire {
        requestID &+= 1
        var data = Wire(); data.put(requestID); data.data.append(payload.data)
        try send(type: type, data: data.data)
        var response = try receive(); let kind = try response.byte()
        guard try response.uint() == requestID else { throw SFTPError(code: 5, message: "SFTP 请求编号不匹配。") }
        if kind == 101 {
            let code = try response.uint(), message = try response.string()
            guard code == 0 && expecting == 101 else { throw SFTPError(code: code, message: "SFTP：\(message)（\(code)）") }
        } else if kind != expecting { throw SFTPError(code: 5, message: "SFTP 响应类型不匹配。") }
        return response
    }
    public static func joining(_ directory: String, _ name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw SFTPError(code: 5, message: "文件名无效。")
        }
        return (directory == "/" ? "" : directory) + "/" + name
    }
    public func realpath(_ path: String) throws -> String {
        var payload = Wire(); payload.string(path)
        var response = try request(16, payload, expecting: 104)
        guard try response.uint() > 0 else { throw SFTPError(code: 5, message: "服务器没有返回路径。") }
        return try response.string()
    }
    public func stat(_ path: String) throws -> RemoteEntry {
        var payload = Wire(); payload.string(path)
        var response = try request(17, payload, expecting: 105)
        return try response.attributes()
    }
    private func closeHandle(_ handle: Data) throws {
        var payload = Wire(); payload.bytes(handle); _ = try request(4, payload, expecting: 101)
    }
    public func list(_ path: String) throws -> [RemoteEntry] {
        var payload = Wire(); payload.string(path)
        var response = try request(11, payload, expecting: 102); let handle = try response.bytes()
        defer { try? closeHandle(handle) }
        var result: [RemoteEntry] = []
        while true {
            var next = Wire(); next.bytes(handle)
            do {
                var page = try request(12, next, expecting: 104); let count = try page.uint()
                guard count > 0, count <= 10000, result.count + Int(count) <= 100000 else { throw SFTPError(code: 5, message: "目录条目数量超出限制。") }
                for _ in 0..<count {
                    let name = try page.string(); _ = try page.bytes()
                    let entry = try page.attributes(name: name)
                    if name != "." && name != ".." { _ = try Self.joining(path, name); result.append(entry) }
                }
            } catch let error as SFTPError where error.code == 1 { break }
        }
        return result.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func open(_ path: String, flags: UInt32) throws -> Data {
        var payload = Wire(); payload.string(path); payload.put(flags); payload.put(0)
        var response = try request(3, payload, expecting: 102); return try response.bytes()
    }
    private func readChunk(_ handle: Data, offset: UInt64, count: UInt32 = 32768) throws -> Data? {
        var payload = Wire(); payload.bytes(handle); payload.put64(offset); payload.put(count)
        do {
            var response = try request(5, payload, expecting: 103)
            let data = try response.bytes()
            guard !data.isEmpty, data.count <= count else { throw SFTPError(code: 5, message: "SFTP 文件数据长度无效。") }
            return data
        } catch let error as SFTPError where error.code == 1 { return nil }
    }
    private func writeChunk(_ handle: Data, offset: UInt64, data: Data) throws {
        var payload = Wire(); payload.bytes(handle); payload.put64(offset); payload.bytes(data)
        _ = try request(6, payload, expecting: 101)
    }
    private func remove(_ path: String) throws { var p = Wire(); p.string(path); _ = try request(13, p, expecting: 101) }
    private func rename(_ source: String, _ target: String) throws {
        var p = Wire(); p.string(source); p.string(target); _ = try request(18, p, expecting: 101)
    }
    private func exists(_ path: String) throws -> RemoteEntry? {
        do {
            var p = Wire(); p.string(path)
            var response = try request(7, p, expecting: 105)
            return try response.attributes()
        } catch let error as SFTPError where error.code == 2 { return nil }
    }
    /// Inspect links themselves so recursive transfers never follow a remote symlink.
    public func attributes(at path: String) throws -> RemoteEntry? { try exists(path) }
    public func createDirectory(_ path: String) throws {
        if let existing = try exists(path) {
            guard existing.isDirectory, !existing.isLink else { throw SFTPError(code: 4, message: "目标不是普通目录：" + path) }
            return
        }
        var payload = Wire(); payload.string(path); payload.put(0)
        _ = try request(14, payload, expecting: 101)
    }
    /// Completed files may be skipped on a directory retry only after byte comparison.
    public func contentsMatch(_ local: URL, remote: String) throws -> Bool {
        guard let entry = try exists(remote), !entry.isDirectory, !entry.isLink,
              let size = entry.size else { return false }
        let source = try FileHandle(forReadingFrom: local); defer { try? source.close() }
        guard try source.seekToEnd() == size else { return false }
        try source.seek(toOffset: 0)
        let handle = try open(remote, flags: 1); defer { try? closeHandle(handle) }
        var offset: UInt64 = 0
        while offset < size {
            try checkCancelled()
            guard let bytes = try readChunk(handle, offset: offset),
                  try source.read(upToCount: bytes.count) == bytes else { return false }
            offset += UInt64(bytes.count)
        }
        return true
    }

    private struct ResumeInfo: Codable, Equatable { var source: String; var size: UInt64; var modified: UInt32?; var sha256: String?; var connection: String? = nil }

    public func download(_ remote: String, to destination: URL, progress: (UInt64, UInt64) -> Void) throws {
        let attributes = try stat(remote)
        guard !attributes.isDirectory, let size = attributes.size else { throw SFTPError(code: 4, message: "请选择普通文件下载。") }
        let identity = SHA256.hash(data: Data(resumeIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
        let info = ResumeInfo(source: try realpath(remote), size: size, modified: attributes.modified, sha256: nil, connection: identity)
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).myterm-part")
        let metadata = partial.appendingPathExtension("json")
        let fm = FileManager.default
        if fm.fileExists(atPath: partial.path) || fm.fileExists(atPath: metadata.path) {
            guard let saved = try? JSONDecoder().decode(ResumeInfo.self, from: Data(contentsOf: metadata)), saved == info,
                  fm.fileExists(atPath: partial.path),
                  (try partial.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
                throw SFTPError(code: 4, message: "本地续传文件与远端不匹配，请更换下载文件名。")
            }
        } else {
            try JSONEncoder().encode(info).write(to: metadata, options: .atomic)
            guard fm.createFile(atPath: partial.path, contents: nil) else { throw SFTPError(code: 4, message: "无法创建下载临时文件。") }
        }
        let local = try FileHandle(forWritingTo: partial); defer { try? local.close() }
        var offset = try local.seekToEnd()
        guard offset <= size else { throw SFTPError(code: 4, message: "续传临时文件大于远端文件。") }
        progress(offset, size)

        let handle = try open(remote, flags: 1); var closed = false
        defer { if !closed { try? closeHandle(handle) } }
        progress(offset, size)
        while offset < size {
            guard let chunk = try readChunk(handle, offset: offset, count: UInt32(min(32768, size - offset))) else {
                throw SFTPError(code: 4, message: "远端文件提前结束，临时文件已保留。")
            }
            try local.write(contentsOf: chunk); offset += UInt64(chunk.count); progress(offset, size)
        }
        let final = try stat(remote)
        guard final.size == info.size && final.modified == info.modified else { throw SFTPError(code: 4, message: "下载期间远端文件发生变化，请更换下载文件名后重试。") }
        try closeHandle(handle); closed = true; try local.synchronize(); try local.close()
        guard Darwin.rename(partial.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try? fm.removeItem(at: metadata)
    }

    public func upload(_ source: URL, to remote: String, progress: (UInt64, UInt64) -> Void) throws {
        let original = try source.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        guard original.isRegularFile == true else { throw SFTPError(code: 4, message: "请选择普通文件上传。") }
        guard try exists(remote) == nil else { throw SFTPError(code: 4, message: "远端已有同名文件，请指定不同名称；现有文件未被覆盖。") }
        let local = try FileHandle(forReadingFrom: source); defer { try? local.close() }
        let size = try local.seekToEnd(); try local.seek(toOffset: 0)
        var hash = SHA256()
        while let chunk = try local.read(upToCount: 1024 * 1024), !chunk.isEmpty { try checkCancelled(); hash.update(data: chunk) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        try local.seek(toOffset: 0)
        let info = ResumeInfo(source: source.lastPathComponent, size: size, modified: nil, sha256: digest)
        let partial = remote + ".myterm-part", metadata = partial + ".json"
        var offset: UInt64 = 0
        let existing = try exists(partial)
        let existingMetadata = try exists(metadata)
        if existing != nil || existingMetadata != nil {
            let metaHandle = try open(metadata, flags: 1); defer { try? closeHandle(metaHandle) }
            guard let data = try readChunk(metaHandle, offset: 0),
                  let saved = try? JSONDecoder().decode(ResumeInfo.self, from: data), saved == info,
                  existing?.size ?? 0 <= size, existing?.isLink != true, existing?.isDirectory != true else {
                throw SFTPError(code: 4, message: "远端续传文件与本地不匹配，请指定不同远端名称。")
            }
            offset = existing?.size ?? 0
        } else {
            // Exclusive creation prevents overwriting unrelated partial files.
            let metaHandle = try open(metadata, flags: 2 | 8 | 32)
            do { try writeChunk(metaHandle, offset: 0, data: JSONEncoder().encode(info)); try closeHandle(metaHandle) }
            catch { try? closeHandle(metaHandle); try? remove(metadata); throw error }
        }
        let handle = try open(partial, flags: existing == nil ? (2 | 8 | 32) : 2)
        var closed = false; defer { if !closed { try? closeHandle(handle) } }
        progress(offset, size)

        try local.seek(toOffset: offset); progress(offset, size)
        while offset < size {
            try checkCancelled()
            guard let chunk = try local.read(upToCount: Int(min(32768, size - offset))), !chunk.isEmpty else {
                throw SFTPError(code: 4, message: "本地文件在传输中变短，临时文件已保留。")
            }
            try writeChunk(handle, offset: offset, data: chunk); offset += UInt64(chunk.count); progress(offset, size)
        }
        let final = try source.resourceValues(forKeys: [.contentModificationDateKey])
        guard try local.seekToEnd() == size, final.contentModificationDate == original.contentModificationDate else {
            throw SFTPError(code: 4, message: "本地文件在传输中发生变化，临时文件已保留。")
        }
        try closeHandle(handle); closed = true
        // SFTP v3 rename refuses an existing destination, even if created during this upload.
        try rename(partial, remote); try? remove(metadata)
    }
}
