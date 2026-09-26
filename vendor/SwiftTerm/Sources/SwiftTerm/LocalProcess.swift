// Local PTY lifecycle. MyTerm changes are documented in MYTERM-PATCH.md.
#if !os(iOS) && !os(Windows)
import Foundation
import Dispatch

public protocol LocalProcessDelegate: AnyObject {
    func processTerminated(_ source: LocalProcess, exitCode: Int32?)
    func dataReceived(slice: ArraySlice<UInt8>)
    func getWindowSize() -> winsize
}

/// Starts and manages a local PTY. Public operations and delegate callbacks belong
/// to `dispatchQueue` (the main queue by default). A launch owns its descriptor
/// until DispatchIO's cleanup handler closes it, independently of the terminal view.
public class LocalProcess {
    public private(set) var childfd: Int32 = -1
    public private(set) var shellPid: pid_t = 0
    public private(set) var running = false
    private weak var delegate: LocalProcessDelegate?
    private let dispatchQueue: DispatchQueue
    private let readQueue = DispatchQueue(label: "SwiftTerm.PTY.read")
    private let readSize = 128 * 1024
    private var io: DispatchIO?
    private var generation = UUID()
    private var streamEnded = false
    private var exitStatus: Int32?
    private var exitObserved = false
    private var exitDelivered = false
    private var loggingDir: String?
    private var logFileCounter = 0
#if os(macOS)
    private var childMonitor: DispatchSourceProcess?
#endif

    public init(delegate: LocalProcessDelegate, dispatchQueue: DispatchQueue? = nil) {
        self.delegate = delegate
        self.dispatchQueue = dispatchQueue ?? .main
    }

    public func startProcess(executable: String = "/bin/bash", args: [String] = [],
                             environment: [String]? = nil, execName: String? = nil,
                             currentDirectory: String? = nil) {
        // EOF may precede process exit. Do not replace a still-owned child.
        guard shellPid == 0, !running else { return }
        releaseIO(stop: true)
        generation = UUID()
        let launch = generation
        streamEnded = false; exitObserved = false; exitDelivered = false; exitStatus = nil
        var size = delegate?.getWindowSize() ?? winsize()
        guard let (pid, fd) = PseudoTerminalHelpers.fork(andExec: executable,
            args: [execName ?? executable] + args,
            env: environment ?? Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            currentDirectory: currentDirectory, desiredWindowSize: &size) else {
            delegate?.processTerminated(self, exitCode: nil)
            return
        }
        shellPid = pid; childfd = fd; running = true
        io = DispatchIO(type: .stream, fileDescriptor: fd, queue: dispatchQueue) { _ in
            close(fd)
        }
        io?.setLimit(lowWater: 1)
        io?.setLimit(highWater: readSize)
        readNext(launch)
#if os(macOS)
        let monitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: dispatchQueue)
        childMonitor = monitor
        monitor.setEventHandler { [weak self] in self?.observeExit(pid: pid, launch: launch) }
        monitor.activate()
#endif
    }

    // Only one read operation is outstanding. Its bounded output is delivered on
    // the owner queue before rearming, so a busy UI backpressures the producer.
    private func readNext(_ launch: UUID) {
        guard launch == generation, !streamEnded, let io else { return }
        io.read(offset: 0, length: readSize, queue: readQueue) { [weak self] done, data, error in
            let bytes = data.map { Array($0) } ?? []
            guard let self else { return }
            self.dispatchQueue.async { [weak self] in
                self?.received(bytes, done: done, error: error, launch: launch)
            }
        }
    }

    private func received(_ bytes: [UInt8], done: Bool, error: Int32, launch: UUID) {
        guard launch == generation, !streamEnded else { return }
        if !bytes.isEmpty {
            if let loggingDir {
                try? Data(bytes).write(to: URL(fileURLWithPath: loggingDir).appendingPathComponent("log-\(logFileCounter)"))
                logFileCounter += 1
            }
            delegate?.dataReceived(slice: bytes[...])
            // Delegates may stop/restart the process synchronously.
            guard launch == generation else { return }
        }
        guard done else { return }
        if bytes.isEmpty || error != 0 {
            streamEnded = true
            running = false
            releaseIO(stop: false)
            deliverExitIfReady()
        } else {
            readNext(launch)
        }
    }

    private func observeExit(pid: pid_t, launch: UUID) {
        guard launch == generation, shellPid == pid else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, WNOHANG) } while result == -1 && errno == EINTR
        guard result != 0 else { return }
        // Clear PID ownership before callbacks: a later terminate must never
        // signal a PID that the operating system has already recycled.
        shellPid = 0
        running = false
        exitObserved = true
        exitStatus = result == pid ? status : nil
#if os(macOS)
        childMonitor?.cancel(); childMonitor = nil
#endif
        deliverExitIfReady()
        // A detached descendant may keep the slave open after the shell exits.
        // Allow buffered output to drain, then cancel the outstanding read; its
        // completion still delivers any bytes before the exit notification.
        dispatchQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == launch, !self.streamEnded else { return }
            self.io?.close(flags: .stop)
        }
    }

    private func deliverExitIfReady() {
        guard exitObserved, streamEnded, !exitDelivered else { return }
        exitDelivered = true
        delegate?.processTerminated(self, exitCode: exitStatus)
    }

    private func releaseIO(stop: Bool) {
        let channel = io
        io = nil; childfd = -1
        if stop { channel?.close(flags: .stop) } else { channel?.close() }
    }

    public func send(data: ArraySlice<UInt8>) {
        guard running, let io else { return }
        data.withUnsafeBytes { buffer in
            io.write(offset: 0, data: DispatchData(bytes: buffer), queue: readQueue) { _, _, _ in }
        }
    }

    /// Close this launch's I/O and signal only a child still owned by this process.
    /// Callers which explicitly terminate are responsible for reaping the child.
    public func terminate() {
        generation = UUID() // Late I/O callbacks must not touch a subsequent launch.
#if os(macOS)
        childMonitor?.cancel(); childMonitor = nil
#endif
        let pid = shellPid
        shellPid = 0; running = false; streamEnded = true
        releaseIO(stop: true)
        if pid > 0 {
            var status: Int32 = 0
            var result: pid_t
            repeat { result = waitpid(pid, &status, WNOHANG) } while result == -1 && errno == EINTR
            if result == 0 { kill(pid, SIGTERM) }
        }
    }

    deinit {
#if os(macOS)
        childMonitor?.cancel()
#endif
        io?.close(flags: .stop)
    }

    public func setHostLogging(directory: String?) { loggingDir = directory }
}
#endif
