import Foundation
import MyTermCore

func checkCodexExecution() throws {
    try CodexExecutionLimits(minutes: 1440, commands: 10000).validate()
    checkThrows(try CodexExecutionLimits(minutes: 0).validate())
    checkThrows(try CodexExecutionLimits(minutes: 1441).validate())
    checkThrows(try CodexExecutionLimits(commands: 0).validate())
    checkThrows(try CodexExecutionLimits(commands: 10001).validate())
    checkEqual(CodexExecutionLimits().commands, 300)
    checkEqual(CodexExecutionPolicy.diagnostics.contains("uptime"), true)
    for value in ["uptime; touch /tmp/unsafe", "python -c 'print(1)'", "df -h > file", "env uptime", "$(uptime)"] {
        checkEqual(CodexExecutionPolicy.diagnostics.contains(value), false)
    }
    checkThrows(try CodexExecutionPolicy.validate("pwd\nwhoami"))
    checkThrows(try CodexExecutionPolicy.validate(String(repeating: "x", count: 4097)))
    let args = try CodexExecutionPolicy.arguments(controlPath: "/tmp/nonexistent-myterm-\(UUID())", host: "localhost", command: "exit 0")
    checkEqual(args.contains("ProxyCommand=/usr/bin/false"), true)
    checkEqual(args.contains("/dev/null"), true)
    func finish(_ job: CodexCommandProcess) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let result = try job.snapshot(offset: 0)
            if result["state"] as? String != "running" { return result }
            Thread.sleep(forTimeInterval: 0.02)
        }
        job.cancel(); throw ConfigurationError.invalid("Command fixture timed out")
    }
    let missing = try CodexCommandProcess(arguments: args)
    checkEqual(try finish(missing)["exit_code"] as? Int32, 255)
    let job = try CodexCommandProcess(executable: "/bin/bash", arguments: ["--noprofile", "--norc", "-c", "printf 'first\\n'; printf 'error\\n' >&2; exit 7"])
    let result = try finish(job)
    checkEqual(result["exit_code"] as? Int32, 7)
    checkEqual((result["output"] as? String)?.contains("first\nerror\n"), true)
    checkThrows(try job.snapshot(offset: -1))
    // Non-UTF-8 remote output must still advance the cursor, otherwise the
    // complete-output gate permanently prevents the next diagnostic command.
    let invalid = try CodexCommandProcess(executable: "/usr/bin/perl", arguments: ["-e", "print chr(128) x 4096"])
    let invalidPage = try finish(invalid)
    checkEqual(invalidPage["total_bytes"] as? Int, 4096)
    checkEqual(invalidPage["next_offset"] as? Int, 2048)
    checkEqual(try invalid.snapshot(offset: 2048)["next_offset"] as? Int, 4096)
    let unicode = try CodexCommandProcess(executable: "/usr/bin/perl", arguments: ["-e", "print 'a' x 2047, pack('C*', 228, 184, 173), 'z'"])
    checkEqual(try finish(unicode)["next_offset"] as? Int, 2047)
    checkEqual(try unicode.snapshot(offset: 2047)["output"] as? String, "中z")
    let releaseFragment = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-output-\(UUID())")
    defer { try? FileManager.default.removeItem(at: releaseFragment) }
    let fragmented = try CodexCommandProcess(executable: "/usr/bin/perl", arguments: ["-e", "$|=1; print pack('C*', 228, 184); while (!-e $ARGV[0]) { select undef,undef,undef,0.01 }; print pack('C', 173)", releaseFragment.path], timeout: 5)
    let fragmentDeadline = Date().addingTimeInterval(3)
    while fragmented.progress.byteCount == 0 && Date() < fragmentDeadline { Thread.sleep(forTimeInterval: 0.005) }
    checkEqual(fragmented.progress.byteCount, 2)
    checkEqual(try fragmented.snapshot(offset: 0)["next_offset"] as? Int, 0)
    try Data().write(to: releaseFragment)
    checkEqual(try finish(fragmented)["output"] as? String, "中")
    let large = try CodexCommandProcess(executable: "/usr/bin/yes", arguments: ["fixture"], timeout: 0.2)
    let bounded = try finish(large)
    checkEqual(bounded["state"] as? String, "cancelled")
    checkEqual(bounded["truncated"] as? Bool, true)
    checkEqual(bounded["total_bytes"] as? Int, 1048576)
    var offset = 0
    repeat {
        let page = try large.snapshot(offset: offset)
        let next = page["next_offset"] as! Int
        checkEqual(next > offset, true); offset = next
    } while offset < 1048576
}
