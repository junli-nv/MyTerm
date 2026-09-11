import Foundation
import Darwin

public struct AskpassRequest: Codable {
    public var token: String
    public var prompt: String
    public var hint: String?
    public init(token: String, prompt: String, hint: String?) { self.token = token; self.prompt = prompt; self.hint = hint }
}
private struct AskpassReply: Codable { var answer: String? }

private enum SocketWire {
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ConfigurationError.invalid("认证通道路径过长。") }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.initializeMemory(as: UInt8.self, repeating: 0); target.copyBytes(from: Array(path.utf8)) }
        return address
    }
    static func configure(_ fd: Int32, seconds: Int = 300) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: seconds, tv_usec: 0), yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    static func read(_ fd: Int32, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            var buffer = [UInt8](repeating: 0, count: count - result.count)
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw ConfigurationError.invalid("认证通道已关闭。") }
            result.append(contentsOf: buffer.prefix(n))
        }
        return result
    }
    static func receive<T: Decodable>(_ fd: Int32) throws -> T {
        let length = try read(fd, count: 4).reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= 65536 else { throw ConfigurationError.invalid("认证请求大小无效。") }
        return try JSONDecoder().decode(T.self, from: read(fd, count: length))
    }
    static func send<T: Encodable>(_ value: T, fd: Int32) throws {
        let body = try JSONEncoder().encode(value)
        guard body.count <= 65536 else { throw ConfigurationError.invalid("认证响应过长。") }
        var length = UInt32(body.count).bigEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }; data.append(body)
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw ConfigurationError.invalid("认证通道写入失败。") }
            offset += n
        }
    }
}

public final class AskpassChannel {
    public let path: String
    public let token = UUID().uuidString + UUID().uuidString
    private let listener: DispatchSourceRead
    private let lock = NSLock()
    private var clients = Set<Int32>()
    private var stopped = false
    public init(path: String, handler: @escaping (AskpassRequest, @escaping (String?) -> Void) -> Void) throws {
        self.path = path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConfigurationError.invalid("无法创建认证通道。") }
        SocketWire.configure(fd); _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var address = try SocketWire.address(path)
        let result = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, listen(fd, 4) == 0 else { Darwin.close(fd); throw ConfigurationError.invalid("无法启动认证通道。") }
        chmod(path, 0o600)
        listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        listener.setCancelHandler { Darwin.close(fd); unlink(path) }
        listener.setEventHandler { [weak self] in
            guard let self else { return }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            SocketWire.configure(client, seconds: 5)
            self.lock.lock()
            if self.stopped { self.lock.unlock(); Darwin.close(client); return }
            self.clients.insert(client); self.lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var uid: uid_t = 0, gid: gid_t = 0
                    guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { throw ConfigurationError.invalid("认证通道身份不匹配。") }
                    let request: AskpassRequest = try SocketWire.receive(client)
                    guard request.token == self.token else { throw ConfigurationError.invalid("认证通道令牌无效。") }
                    handler(request) { answer in
                        DispatchQueue.global(qos: .userInitiated).async {
                            try? SocketWire.send(AskpassReply(answer: answer), fd: client)
                            self.finish(client)
                        }
                    }
                } catch { self.finish(client) }
            }
        }
        listener.resume()
    }
    private func finish(_ fd: Int32) { lock.lock(); clients.remove(fd); Darwin.close(fd); lock.unlock() }
    public func stop() {
        lock.lock(); stopped = true
        for client in clients { shutdown(client, SHUT_RDWR) }
        lock.unlock(); listener.cancel()
    }
    deinit { stop() }
    public static func answer(path: String, token: String, prompt: String, hint: String?) throws -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConfigurationError.invalid("无法连接认证通道。") }
        defer { Darwin.close(fd) }; SocketWire.configure(fd)
        var address = try SocketWire.address(path)
        let status = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard status == 0 else { throw ConfigurationError.invalid("认证会话已关闭。") }
        try SocketWire.send(AskpassRequest(token: token, prompt: prompt, hint: hint), fd: fd)
        let reply: AskpassReply = try SocketWire.receive(fd)
        return reply.answer
    }
}
