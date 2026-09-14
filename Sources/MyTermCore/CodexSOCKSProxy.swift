import Foundation
import Network

/// Per-Codex HTTP CONNECT listener forwarding through a configured SOCKS5 proxy.
/// Loopback-only, random HTTP proxy credential, bounded headers/connections;
/// destination names are resolved by SOCKS5, never by the local DNS resolver.
public final class CodexSOCKSProxy {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MyTerm.CodexSOCKS")
    private let credential = UUID().uuidString + UUID().uuidString
    private final class Pool { var tunnels: [UUID: Tunnel] = [:] }
    private let pool = Pool()
    public private(set) var port: UInt16 = 0
    public init(host: String, port: UInt16, username: String, password: String) throws {
        guard !host.isEmpty, username.utf8.count <= 255, password.utf8.count <= 255 else { throw ConfigurationError.invalid("Invalid SOCKS5 proxy credentials") }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed, .cancelled: ready.signal(); default: break }
        }
        let expected = "Basic " + Data(("myterm:" + credential).utf8).base64EncodedString()
        listener.newConnectionHandler = { [weak self] client in
            guard let self, self.pool.tunnels.count < 32 else { client.cancel(); return }
            let id = UUID()
            let tunnel = Tunnel(client: client, proxyHost: host, proxyPort: port, user: username, password: password, expected: expected, queue: self.queue) { [weak self] in self?.pool.tunnels.removeValue(forKey: id) }
            self.pool.tunnels[id] = tunnel; tunnel.start()
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let bound = listener.port else { listener.cancel(); throw ConfigurationError.invalid("Cannot start local Codex proxy") }
        self.port = bound.rawValue
    }
    public func environment(base: [String: String]) throws -> [String: String] {
        var settings = CodexConnection(); settings.proxyMode = .http
        settings.host = "127.0.0.1"; settings.port = String(port); settings.username = "myterm"
        return try settings.environment(base: base, password: credential)
    }
    deinit {
        listener.cancel()
        // Handler callbacks own tunnels only until cancellation completes.
        let pool = self.pool
        queue.async { Array(pool.tunnels.values).forEach { $0.close() }; pool.tunnels.removeAll() }
    }
    private final class Tunnel {
        let client: NWConnection
        let upstream: NWConnection
        let queue: DispatchQueue
        let user: String, password: String, expected: String
        var header = Data()
        var finished = false
        var timeout: DispatchWorkItem?
        let done: () -> Void
        init(client: NWConnection, proxyHost: String, proxyPort: UInt16, user: String, password: String, expected: String, queue: DispatchQueue, done: @escaping () -> Void) {
            self.client = client; self.queue = queue; self.user = user; self.password = password; self.expected = expected; self.done = done
            upstream = NWConnection(host: NWEndpoint.Host(proxyHost), port: NWEndpoint.Port(rawValue: proxyPort)!, using: .tcp)
        }
        func start() {
            let timer = DispatchWorkItem { [weak self] in self?.close() }; timeout = timer
            queue.asyncAfter(deadline: .now() + 15, execute: timer)
            client.start(queue: queue); readHeader()
        }
        func close() {
            guard !finished else { return }; finished = true
            timeout?.cancel(); timeout = nil; client.cancel(); upstream.cancel(); done()
        }
        func send(_ connection: NWConnection, _ data: Data, then: @escaping () -> Void) {
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, !self.finished else { return }
                if error != nil { self.close() } else { then() }
            })
        }
        func receive(_ count: Int, then: @escaping (Data) -> Void) {
            upstream.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, complete, error in
                guard let self, !self.finished else { return }
                guard error == nil, let data, data.count == count else { self.close(); return }
                then(data)
            }
        }
        func readHeader() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
                guard let self, !self.finished else { return }
                guard error == nil, let data, !data.isEmpty else { self.close(); return }
                self.header.append(data)
                guard self.header.count <= 16384 else { self.close(); return }
                guard let end = self.header.range(of: Data("\r\n\r\n".utf8)) else { self.readHeader(); return }
                let text = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
                let lines = text.components(separatedBy: "\r\n")
                let request = (lines.first ?? "").split(separator: " ")
                let authenticated = lines.dropFirst().contains { line in
                    let fields = line.split(separator: ":", maxSplits: 1)
                    return fields.count == 2 && fields[0].lowercased() == "proxy-authorization" && fields[1].trimmingCharacters(in: .whitespaces) == self.expected
                }
                guard authenticated, request.count == 3, request[0] == "CONNECT",
                      let separator = request[1].lastIndex(of: ":"),
                      let port = UInt16(request[1][request[1].index(after: separator)...]), port > 0 else {
                    self.send(self.client, Data("HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n".utf8)) { self.close() }; return
                }
                let host = String(request[1][..<separator]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                guard !host.isEmpty, host.utf8.count <= 255, !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { self.close(); return }
                let extra = Data(self.header[end.upperBound...]); self.header = Data()
                self.upstream.stateUpdateHandler = { [weak self] state in
                    guard let self, !self.finished else { return }
                    switch state {
                    case .ready: self.negotiate(host: host, port: port, extra: extra)
                    case .failed: self.close()
                    default: break
                    }
                }
                self.upstream.start(queue: self.queue)
            }
        }
        func negotiate(host: String, port: UInt16, extra: Data) {
            let method: UInt8 = user.isEmpty ? 0 : 2
            send(upstream, Data([5, 1, method])) {
                self.receive(2) { response in
                    guard response == Data([5, method]) else { self.close(); return }
                    if method == 2 {
                        self.send(self.upstream, Data([1, UInt8(self.user.utf8.count)]) + Data(self.user.utf8) + Data([UInt8(self.password.utf8.count)]) + Data(self.password.utf8)) {
                            self.receive(2) { auth in
                                guard auth == Data([1, 0]) else { self.close(); return }
                                self.connect(host: host, port: port, extra: extra)
                            }
                        }
                    } else { self.connect(host: host, port: port, extra: extra) }
                }
            }
        }
        func connect(host: String, port: UInt16, extra: Data) {
            send(upstream, Data([5, 1, 0, 3, UInt8(host.utf8.count)]) + Data(host.utf8) + Data([UInt8(port >> 8), UInt8(port & 255)])) {
                self.receive(4) { reply in
                    guard reply[0] == 5, reply[1] == 0 else { self.close(); return }
                    func drain(_ count: Int) {
                        self.receive(count + 2) { _ in
                            self.send(self.client, Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)) {
                                self.timeout?.cancel(); self.timeout = nil
                                self.pump(self.upstream, to: self.client)
                                if extra.isEmpty { self.pump(self.client, to: self.upstream) }
                                else { self.send(self.upstream, extra) { self.pump(self.client, to: self.upstream) } }
                            }
                        }
                    }
                    switch reply[3] {
                    case 1: drain(4)
                    case 4: drain(16)
                    case 3: self.receive(1) { drain(Int($0[0])) }
                    default: self.close()
                    }
                }
            }
        }
        func pump(_ source: NWConnection, to target: NWConnection) {
            source.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, complete, error in
                guard let self, !self.finished else { return }
                guard error == nil else { self.close(); return }
                if let data, !data.isEmpty {
                    self.send(target, data) { if complete { self.close() } else { self.pump(source, to: target) } }
                } else if complete { self.close() } else { self.pump(source, to: target) }
            }
        }
    }
}
