import Foundation
import SwiftTerm
import Darwin
import MyTermCore

final class PTYTests {
    final class Probe: LocalProcessDelegate {
        let outputReceived: CheckExpectation
        let terminated: CheckExpectation
        var output = ""
        var matched = false
        var outputAtExit = ""
        var exitCount = 0
        init(outputReceived: CheckExpectation, terminated: CheckExpectation) {
            self.outputReceived = outputReceived
            self.terminated = terminated
        }
        func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
            outputAtExit = output; exitCount += 1; terminated.fulfill()
        }
        func dataReceived(slice: ArraySlice<UInt8>) {
            output += String(decoding: slice, as: UTF8.self)
            if !matched && output.contains("MYTERM_PTY_OK") && output.contains("37 101") && output.contains("你好") {
                matched = true
                outputReceived.fulfill()
            }
        }
        func getWindowSize() -> winsize { winsize(ws_row: 37, ws_col: 101, ws_xpixel: 0, ws_ypixel: 0) }
    }

    func testBashPTYInputOutputSizeAndExit() {
        let output = expectation(description: "PTY delivers output, Unicode, window size and interactive input")
        let exit = expectation(description: "Bash exits")
        let probe = Probe(outputReceived: output, terminated: exit)
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/bash", args: ["--noprofile", "--norc", "-c",
            "test -t 0 && test -t 1 || exit 9; stty size; read -r answer; if [ \"$answer\" = ping ]; then printf 'MYTERM_PTY_OK 你好\\n'; fi"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin", "LANG=en_US.UTF-8"])
        let pid = process.shellPid
        checkGreaterThan(pid, 0)
        process.send(data: Array("ping\n".utf8)[...])
        wait(for: [output, exit], timeout: 8)
        // Let the termination callback finish cleaning up its process monitor.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checkFalse(process.running)
    }

    func testCloseReapsInteractiveShell() {
        let probe = Probe(outputReceived: CheckExpectation(), terminated: CheckExpectation())
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/bash", args: ["--noprofile", "--norc", "-i"])
        let pid = process.shellPid
        checkGreaterThan(pid, 0)
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        process.terminate()
        ChildProcessCleanup.reap(pid)
        let deadline = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        checkEqual(kill(pid, 0), -1)
        checkEqual(errno, ESRCH)
    }

    func testRetainedExitResources() {
        var retained: [LocalProcess] = []
        for iteration in 0..<100 {
            let probe = Probe(outputReceived: CheckExpectation(), terminated: CheckExpectation(description: "retained PTY iteration \(iteration)"))
            probe.matched = true // Bulk-output checks must not rescan the entire transcript per chunk.
            let process = LocalProcess(delegate: probe)
            let script = iteration == 0
                ? "printf START; /usr/bin/head -c 2097152 /dev/zero | /usr/bin/tr '\\0' x; printf END"
                : (iteration == 1 ? "printf END; exec </dev/null >/dev/null 2>&1; /bin/sleep 0.1" : "printf END")
            process.startProcess(executable: "/bin/bash", args: ["--noprofile", "--norc", "-c", script])
            let fd = process.childfd
            checkGreaterThan(fd, -1)
            let end = Date().addingTimeInterval(10)
            while !probe.terminated.fulfilled && Date() < end {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            if !probe.terminated.fulfilled {
                fail("PTY iteration \(iteration), bytes=\(probe.output.utf8.count), running=\(process.running), pid=\(process.shellPid), fd=\(process.childfd)")
            }
            checkEqual(probe.exitCount, 1)
            checkEqual(probe.outputAtExit.hasSuffix("END"), true)
            if iteration == 0 { checkEqual(probe.outputAtExit.utf8.count, 2097152 + 8) }
            checkEqual(process.shellPid, 0)
            checkEqual(process.childfd, -1)
            let deadline = Date().addingTimeInterval(1)
            while fcntl(fd, F_GETFD) != -1 && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            checkEqual(fcntl(fd, F_GETFD), -1)
            checkEqual(errno, EBADF)
            // Keep the process objects alive as disconnected tabs do.
            retained.append(process)
            process.terminate() // Must be harmless after reaping.
        }
        checkEqual(retained.count, 100)
        let process = retained[0]
        // Old cancelled callbacks must not close a new launch's descriptor.
        process.startProcess(executable: "/bin/bash", args: ["-c", "sleep 0.2"])
        let pid = process.shellPid
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checkEqual(process.running, true)
        process.terminate(); ChildProcessCleanup.reap(pid)
    }

    func testUncooperativeChildCleanup() {
        let probe = Probe(outputReceived: CheckExpectation(), terminated: CheckExpectation())
        probe.matched = true
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/bash", args: ["-c", "trap '' HUP TERM; printf READY; exec /bin/sleep 30"])
        let pid = process.shellPid
        let readyDeadline = Date().addingTimeInterval(3)
        while !probe.output.contains("READY") && Date() < readyDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        checkEqual(probe.output.contains("READY"), true)
        kill(pid, SIGHUP)
        process.terminate()
        ChildProcessCleanup.reap(pid)
        let deadline = Date().addingTimeInterval(4)
        while kill(pid, 0) == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        checkEqual(kill(pid, 0), -1)
        checkEqual(errno, ESRCH)
        checkEqual(process.childfd, -1)
    }
}
