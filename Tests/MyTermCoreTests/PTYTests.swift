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
        init(outputReceived: CheckExpectation, terminated: CheckExpectation) {
            self.outputReceived = outputReceived
            self.terminated = terminated
        }
        func processTerminated(_ source: LocalProcess, exitCode: Int32?) { terminated.fulfill() }
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
}
