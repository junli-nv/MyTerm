import AppKit
import MyTermCore

/// Exercises the actual TerminalView interception and helper bridge over a real PTY.
final class ZmodemWindowCheck {
    private let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("myterm-ztest-\(UUID().uuidString)")
    private let content = Data((0..<180000).map { UInt8(truncatingIfNeeded: $0 * 17) })
    private var session: TerminalSession?
    private var window: NSWindow?
    private var phase = 0
    private var deadline = Date()
    private var timer: Timer?
    private var completion: ((Result<Void, Error>) -> Void)?

    func run(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        do {
            var meter = ZmodemRateMeter(now: 0)
            meter.add(1000)
            guard meter.sample(now: 1) == 1000 else { throw ConfigurationError.invalid("Zmodem initial rate mismatch") }
            meter.add(1000)
            guard meter.sample(now: 2) == 1000, meter.sample(now: 3) == 500,
                  meter.sample(now: 4) == 0, meter.average(now: 4) == 500 else {
                throw ConfigurationError.invalid("Zmodem smoothing, idle decay or average mismatch")
            }
            for dir in ["source", "receive", "remote", "drag"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
            try content.write(to: root.appendingPathComponent("source/binary.bin"))
            for dir in ["receive", "remote", "drag"] { try Data("old data".utf8).write(to: root.appendingPathComponent(dir + "/binary.bin")) }
            try startPhase()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
                guard let bridge = session?.terminal.zmodem else { finish(error: "Missing Zmodem bridge"); return }
                if Date() > deadline { finish(error: "Zmodem PTY timeout at phase \(phase): \(bridge.status)"); return }
                guard bridge.status == "Zmodem 传输完成" else { return }
                guard bridge.rateIsAverage, bridge.bytesPerSecond > 0,
                      bridge.transferredBytes >= UInt64(phase >= 3 ? content.count / 2 : content.count), bridge.receiving == (phase == 0 || phase == 4) else {
                    finish(error: "Zmodem rate accounting phase \(phase): bytes=\(bridge.transferredBytes), rate=\(bridge.bytesPerSecond), receiving=\(bridge.receiving), average=\(bridge.rateIsAverage)"); return
                }
                let file = root.appendingPathComponent((phase == 0 || phase == 4) ? "receive/binary.bin" : phase == 2 ? "drag/binary.bin" : "remote/binary.bin")
                guard (try? Data(contentsOf: file)) == content else { finish(error: "Zmodem PTY bytes differ"); return }
                if phase >= 3 && bridge.transferredBytes >= UInt64(content.count) {
                    finish(error: "Zmodem resume retransmitted the whole file"); return
                }
                guard (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).sorted()) == ["binary.bin"] else {
                    finish(error: "Zmodem created a renamed duplicate"); return
                }
                session?.stop(); window?.close(); session = nil; window = nil
                if phase < 4 {
                    phase += 1
                    do { try startPhase() } catch { finish(error: error.localizedDescription) }
                } else { finish(error: nil) }
            }
        } catch { finish(error: error.localizedDescription) }
    }
    private func startPhase() throws {
        let receiver = ["/opt/homebrew/bin/lrz", "/usr/local/bin/lrz"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        let sender = ["/opt/homebrew/bin/lsz", "/usr/local/bin/lsz"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let receiver, let sender else { throw ConfigurationError.invalid("Zmodem test requires lrzsz") }
        let source = root.appendingPathComponent("source/binary.bin")
        let downloading = phase == 0 || phase == 4
        let remoteExecutable = downloading ? sender : phase == 2 ? "/bin/bash" : receiver
        let remoteArguments = downloading ? ["--binary", "--escape", "--", source.path] : phase != 2 ? ["--binary", "--escape", phase == 3 ? "--resume" : "--overwrite"] : ["--noprofile", "--norc", "-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin; exec /bin/bash --noprofile --norc -i"]
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/trzsz").path
        let server = Server(host: "localhost")
        if phase == 3 { try content.prefix(content.count / 2).write(to: root.appendingPathComponent("remote/binary.bin")) }
        if phase == 4 {
            let partial = try ZmodemDownload(destination: root.appendingPathComponent("receive"), identity: server.id.uuidString, storage: root.appendingPathComponent("staging"))
            try content.prefix(content.count / 2).write(to: partial.directory.appendingPathComponent("binary.bin"))
        }
        let session = TerminalSession(label: "Zmodem 自检", executable: helper,
            arguments: ["--dragfile", remoteExecutable] + remoteArguments,
            server: server, directory: root.appendingPathComponent(phase == 2 ? "drag" : "remote").path)
        session.terminal.zmodem?.testResumeUpload = phase == 3
        session.terminal.zmodem?.testDownloadStorage = root.appendingPathComponent("staging")
        session.terminal.zmodem?.conflictHandler = { _, _, allowed in allowed ? .overwrite : .cancel }
        session.terminal.zmodem?.testSelection = { [root] receiving in receiving ? [root.appendingPathComponent("receive")] : [source] }
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 600, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "MyTerm Zmodem 自检"
        window.contentView = session.terminal; window.orderFront(nil)
        self.session = session; self.window = window; deadline = Date().addingTimeInterval(25)
        session.start()
        if phase == 2 {
            session.terminal.zmodem?.testSelection = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard session.terminal.zmodem?.uploadDroppedFiles([source]) == true else { self.finish(error: "Drop upload was rejected"); return }
            }
        }
    }
    private func finish(error: String?) {
        timer?.invalidate(); timer = nil; session?.stop(); window?.close()
        session = nil; window = nil; try? FileManager.default.removeItem(at: root)
        let callback = completion; completion = nil
        if let error { callback?(.failure(ConfigurationError.invalid(error))) }
        else { print("PASS: Zmodem overwrite without renamed duplicates, partial upload/download resume and dropped-file upload; directional throughput, idle decay and final average through real PTY"); callback?(.success(())) }
    }
}
