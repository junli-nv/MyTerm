import Foundation
import MyTermCore

func checkCodexIntegration() throws {
    var connection = CodexConnection()
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
    let once = CodexConnection.sessionPrompt(id: id, monitor: false)
    checkEqual(once.contains(id.uuidString), true)
    checkEqual(once.contains("Continuously monitor"), false)
    checkEqual(CodexConnection.sessionPrompt(id: id, monitor: true).contains("stopped=true"), true)
    var clock: TimeInterval = 0, probes = 0
    let waited = try CodexMCP.watch(arguments: ["session_id": id.uuidString, "cursor": "initial"], call: { name, args in
        checkEqual(name, "watch_output")
        checkEqual(args["cursor"] as? String, probes == 0 ? "initial" : "next")
        probes += 1
        return ["unchanged": probes < 3, "cursor": "next", "text": probes < 3 ? "" : "new output"]
    }, pause: { clock += $0 }, now: { clock })
    checkEqual(probes, 3); checkEqual(clock, 4)
    checkEqual(waited["text"] as? String, "new output")
    probes = 0; clock = 0
    _ = try CodexMCP.watch(arguments: [:], call: { _, _ in probes += 1; return ["unchanged": true, "cursor": "idle"] }, pause: { clock += $0 }, now: { clock })
    checkEqual(clock, 20); checkEqual(probes, 11)
    probes = 0
    _ = try CodexMCP.watch(arguments: [:], call: { _, _ in probes += 1; return ["stopped": true, "unchanged": true] }, pause: { _ in fatalError("Stopped monitor waited") })
    checkEqual(probes, 1)
    checkEqual(args.contains("mcp_servers.myterm.required=true"), true)
    for tool in ["list_sessions", "read_output", "watch_output", "capture_history", "read_history_page"] {
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
    var invoked = false
    let initReply = CodexMCP.response(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]]) { _, _ in invoked = true; return [:] }
    checkEqual((initReply?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
    checkEqual(invoked, false)
    let unknown = CodexMCP.response(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "execute_command"]]) { _, _ in invoked = true; return [:] }
    checkEqual(unknown?["error"] != nil, true); checkEqual(invoked, false)
}
