import Foundation
import MyTermCore

func checkCodexIntegration() throws {
    try checkCodexExecution()
    try checkCodexCommandWait()
    var connection = CodexConnection()
    checkEqual(connection.executable, "/opt/homebrew/bin/codex")
    let custom = CodexConnection(executable: "/custom/bin/codex")
    checkEqual(try JSONDecoder().decode(CodexConnection.self, from: JSONEncoder().encode(custom)).executable, custom.executable)
    let base = ["HTTP_PROXY": "http://old.invalid", "https_proxy": "http://old.invalid", "NO_PROXY": "*", "SHELL": "/bin/bash"]
    checkEqual(try connection.environment(base: base, password: ""), base)
    connection.proxyMode = .http
    checkThrows(try connection.environment(base: base, password: ""))
    connection.port = "7890"; connection.username = "a@b"
    var ssh = Server(host: "ssh-fixture.invalid")
    ssh.proxy = NetworkProxy(kind: .http, host: "ssh-proxy.invalid", port: "1234")
    let originalSSH = try ssh.connectionArguments()
    let env = try connection.environment(base: base, password: "p@ss:/word")
    checkEqual(try ssh.connectionArguments(), originalSSH)
    ssh.proxy = NetworkProxy(kind: .socks5, host: "another-ssh-proxy.invalid", port: "5678")
    checkEqual(try connection.environment(base: base, password: "p@ss:/word"), env)
    checkEqual(base["HTTP_PROXY"], "http://old.invalid")
    checkEqual(env["SHELL"], "/bin/bash")
    checkEqual(env["HTTPS_PROXY"], env["https_proxy"])
    checkEqual(env["ALL_PROXY"], env["HTTP_PROXY"])
    checkEqual(env["NO_PROXY"], "localhost,127.0.0.1,::1")
    checkEqual(URLComponents(string: env["HTTP_PROXY"]!)?.password, "p@ss:/word")
    checkEqual(URLComponents(string: env["HTTP_PROXY"]!)?.user, "a@b")
    connection.proxyMode = .socks5
    checkEqual(try connection.proxyURL(password: "")?.hasPrefix("socks5h://"), true)
    connection.host = "bad/host"; checkThrows(try connection.proxyURL(password: ""))
    connection.host = "localhost"; connection.port = "65536"; checkThrows(try connection.proxyURL(password: ""))
    let args = try CodexConnection.launchArguments(appExecutable: "/tmp/My Term'quoted.app/Contents/MacOS/MyTerm")
    checkEqual(args.contains("read-only"), true)
    checkEqual(Array(args.prefix(2)), CodexConnection.authenticationArguments)
    checkEqual(args.contains("mcp_servers.myterm.args=[\"--myterm-mcp\"]"), true)
    let id = UUID()
    let resumed = try CodexConnection.launchArguments(appExecutable: "/tmp/My Term.app/MyTerm", association: id, resume: true)
    checkEqual(Array(resumed.suffix(2)), ["resume", "--all"])
    checkEqual(resumed.contains("mcp_servers.myterm.env.MYTERM_CODEX_ASSOCIATION=\"" + id.uuidString + "\""), true)
    checkFalse(resumed.contains(where: { $0.contains("developer_instructions=") }))
    let localArgs = try CodexConnection.launchArguments(appExecutable: "/tmp/My Term.app/MyTerm", localDirectory: "/tmp/work '中文'")
    checkEqual(localArgs[localArgs.firstIndex(of: "--cd")! + 1], "/tmp/work '中文'")
    checkEqual(localArgs[localArgs.firstIndex(of: "--sandbox")! + 1], "workspace-write")
    checkEqual(localArgs[localArgs.firstIndex(of: "--ask-for-approval")! + 1], "on-request")
    checkEqual(args.contains("workspace-write"), false)
    checkEqual(localArgs.contains(where: { $0.contains("enabled=false") }), true)
    checkEqual(localArgs.contains(where: { $0.contains("required=false") }), true)
    checkEqual(localArgs.contains(where: { $0.contains("session_id") || $0.contains("mcp_servers.myterm.command=") }), false)
    for launch in [args, resumed, localArgs] {
        checkFalse(launch.contains("--no-alt-screen"))
        checkFalse(launch.contains(where: { $0.hasPrefix("tui.") }))
    }
    let once = CodexConnection.sessionPrompt(id: id)
    checkEqual(once.contains(id.uuidString), true)
    checkEqual(once.contains("Continuously monitor"), false)
    checkEqual(once.contains("First call capture_history"), false)
    checkEqual(once.contains("wait for my task"), true)
    checkEqual(once.contains("all_output_delivered=true"), true)
    checkEqual(CodexConnection.sessionPrompt(id: id, includeHistory: true).contains("First call capture_history"), true)
    checkEqual(CodexMCP.tools.contains { $0["name"] as? String == "watch_output" }, false)
    let retired = CodexMCP.response(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "watch_output"]]) { _, _ in
        fail("Removed monitor contacted the application")
    }
    let retiredText = ((retired?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    checkEqual(retiredText.contains("\"stopped\":true"), true)
    checkEqual(CodexMCP.tools.contains { $0["name"] as? String == "propose_plan" }, false)
    checkEqual(args.contains { $0.contains("propose_plan") }, false)
    let retiredPlan = CodexMCP.response(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "propose_plan", "arguments": ["plan": "sensitive plan text"]]]) { _, _ in
        fail("Removed plan tool contacted the application")
    }
    let planText = ((retiredPlan?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    checkEqual(planText.contains("not_required"), true)
    checkEqual(planText.contains("sensitive plan text"), false)
    checkEqual(args.contains("mcp_servers.myterm.required=true"), true)
    for tool in ["list_sessions", "read_output", "capture_history", "read_history_page"] {
        checkEqual(args.contains("mcp_servers.myterm.tools.\(tool).approval_mode=\"approve\""), true)
    }
    checkEqual(args.contains("never"), false)
    checkEqual(args.contains("--dangerously-bypass-approvals-and-sandbox"), false)
    var pages = CodexHistoryPages()
    let longText = "GPU 6 details\n" + String(repeating: "中文 diagnostics\n", count: 2500) + "last sample"
    let captured = pages.capture(session: "ssh", text: longText, maximumBytes: 262144, truncated: false)
    var cursor = captured["next_cursor"] as? String, restored = ""
    while let next = cursor {
        let page = try pages.page(session: "ssh", cursor: next)
        let text = page["text"] as! String
        checkEqual(text.utf8.count <= 4000, true)
        restored += text; cursor = page["next_cursor"] as? String
    }
    checkEqual(restored, longText)
    checkEqual(captured["truncated"] as? Bool, false)
    checkThrows(try pages.page(session: "private", cursor: captured["next_cursor"] as! String))
    let clipped = pages.capture(session: "ssh", text: longText, maximumBytes: 4096, truncated: false)
    checkEqual(clipped["truncated"] as? Bool, true)
    checkEqual((clipped["total_bytes"] as! Int) <= 4096, true)
    pages.clear()
    checkThrows(try pages.page(session: "ssh", cursor: captured["next_cursor"] as! String))
    for path in ["/Applications/MyTerm.app/Contents/MacOS/MyTerm", "/tmp/My Term\"quoted\\路径/MyTerm"] {
        let built = try CodexConnection.launchArguments(appExecutable: path)
        let encoded = built.first(where: { $0.hasPrefix("mcp_servers.myterm.command=") })!
        checkEqual(encoded.contains("\\/"), false)
        let value = String(encoded.dropFirst("mcp_servers.myterm.command=".count))
        checkEqual(try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) as? String, path)
    }
    checkEqual(CodexFailureDiagnosis.message(for: "required MCP servers failed to initialize: myterm: No such file or directory (os error 2)")?.contains("找不到 MyTerm MCP"), true)
    checkEqual(CodexFailureDiagnosis.message(for: "401 Unauthorized")?.contains("登录凭据"), true)
    checkEqual(CodexFailureDiagnosis.message(for: "error sending request")?.contains("专用代理"), true)
    checkEqual(CodexFailureDiagnosis.message(for: "arbitrary failure"), nil)
    var cache = CodexSnapshotCache()
    let first = cache.read(scope: "one", text: "hello", cursor: nil)
    let second = cache.read(scope: "one", text: "hello world", cursor: first["cursor"] as? String)
    checkEqual(second["text"] as? String, " world"); checkEqual(second["reset"] as? Bool, false)
    checkEqual(cache.read(scope: "two", text: "hello world", cursor: second["cursor"] as? String)["reset"] as? Bool, true)
    checkEqual(cache.read(scope: "one", text: "redrawn", cursor: second["cursor"] as? String)["reset"] as? Bool, true)
    cache.clear()
    checkEqual(cache.read(scope: "one", text: "hello world", cursor: second["cursor"] as? String)["reset"] as? Bool, true)
    // Exercise the actual MCP wire response, including explicit detailed replies.
    for tool in ["execute_command", "command_status", "cancel_command"] {
        for verbose in [false, true] {
            for state in ["awaiting_approval", "queued", "running", "completed", "failed", "cancelled"] {
                let fixture: [String: Any] = ["command": "printf hello", "reason": "diagnosis", "session_id": "session",
                    "job_id": "job", "state": state, "output": "full output\n中文", "next_offset": 123,
                    "total_bytes": 456, "all_output_delivered": false, "incomplete": true,
                    "incomplete_reason": "timeout", "truncated": true, "exit_code": 1,
                    "execution_authorization": ["active": true, "approval_mode": "session_always_allow",
                        "guidance": "long explanation", "source": "MyTerm user interface", "timeout_seconds": 60]]
                var args: [String: Any] = [:]
                if verbose { args["verbose"] = true }
                let reply = CodexMCP.response(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                    "params": ["name": tool, "arguments": args]]) { _, forwarded in
                        checkEqual(forwarded["verbose"] == nil, true)
                        return fixture
                    }
                let result = reply?["result"] as! [String: Any]
                let content = result["content"] as! [[String: Any]]
                let decoded = try JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8)) as! [String: Any]
                checkEqual(decoded["command"] as? String, verbose ? "printf hello" : nil)
                let authorization = decoded["execution_authorization"] as! [String: Any]
                checkEqual(authorization["guidance"] as? String, verbose ? "long explanation" : nil)
                checkEqual(authorization["approval_mode"] as? String, "session_always_allow")
                for key in ["job_id", "state", "output", "next_offset", "total_bytes", "all_output_delivered",
                            "incomplete", "incomplete_reason", "truncated", "exit_code"] {
                    checkEqual(NSDictionary(dictionary: [key: decoded[key]!]), NSDictionary(dictionary: [key: fixture[key]!]))
                }
            }
        }
    }
    var invoked = false
    let initReply = CodexMCP.response(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]]) { _, _ in invoked = true; return [:] }
    checkEqual((initReply?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
    checkEqual(invoked, false)
    let unknown = CodexMCP.response(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "unknown_command"]]) { _, _ in invoked = true; return [:] }
    checkEqual(unknown?["error"] != nil, true); checkEqual(invoked, false)
}

private func checkCodexCommandWait() throws {
    for terminal in ["completed", "failed", "cancelled", "awaiting_approval", "rejected"] {
        var clock: TimeInterval = 0
        var count = 0
        let reply = try CodexCommandWait.reply(tool: "command_status", now: { clock }, sleep: { clock += $0 }) {
            count += 1
            return ["state": count == 1 ? "running" : terminal, "output": ""]
        }
        checkEqual(reply["state"] as? String, terminal)
        checkEqual(count, 2)
    }
    var clock: TimeInterval = 0
    var count = 0
    _ = try CodexCommandWait.reply(tool: "command_status", now: { clock }, sleep: { clock += $0 }) {
        count += 1; return ["state": "running", "output": ""]
    }
    checkEqual(clock, 20); checkEqual(count, 21)
    for tool in ["command_status", "execute_command", "cancel_command"] {
        for value: [String: Any] in [["state": "running", "output": "new output"],
                                    ["state": "awaiting_approval", "output": ""],
                                    ["state": "running", "output": "", "incomplete": true]] {
            var slept = false
            let reply = try CodexCommandWait.reply(tool: tool, sleep: { _ in slept = true }) { value }
            checkEqual(slept, false)
            checkEqual(NSDictionary(dictionary: reply), NSDictionary(dictionary: value))
        }
    }
    var fetches = 0
    checkThrows(try CodexCommandWait.reply(tool: "command_status", sleep: { _ in }) {
        fetches += 1
        if fetches > 1 { throw ConfigurationError.invalid("revoked") }
        return ["state": "running", "output": ""]
    })
}
