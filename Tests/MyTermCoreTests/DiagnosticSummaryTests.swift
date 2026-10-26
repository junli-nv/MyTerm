import Foundation
import MyTermCore

func checkDiagnosticSummary() throws {
    func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { checkEqual(value, true, file: file, line: line) }
    let denied = CodexMCPHealthCheck.Result(success: false, stage: .launch, reason: "permission_denied", code: 13)
    let failed = CodexMCPHealthCheck.Result(success: false, stage: .initialize, reason: "host_exited", code: 0)
    let healthy = CodexMCPHealthCheck.Result(success: true, stage: .tools, reason: "ok", code: nil)
    checkTrue(CodexDiagnosticSummary.explanation(denied, language: .chinese).contains("不等于已确认 Gatekeeper"))
    checkTrue(CodexDiagnosticSummary.explanation(failed, language: .english).contains("cause is unknown"))
    checkTrue(CodexDiagnosticSummary.explanation(healthy, language: .english).contains("does not prove intermittent failures"))
    for reason in ["launch_failed", "timeout", "invalid_reply", "reply_limit", "read_failed", "write_failed", "private-sentinel"] {
        let result = CodexMCPHealthCheck.Result(success: false, stage: .initialize, reason: reason, code: nil)
        let text = CodexDiagnosticSummary.explanation(result, language: .english)
        checkTrue(text.contains("Next step:")); checkFalse(text.contains("private-sentinel"))
    }
    let empty = try CodexDiagnosticSummary.document(Data("{}".utf8), language: .chinese)
    checkTrue(empty.contains("尚无主动接口检查结果")); checkTrue(empty.contains("没有事件不等于没有故障"))
    // Normal EOF is not a crash. A passing probe must not hide another helper's failed write.
    let fixture = Data(#"{"captured":"2026-10-26T00:00:00Z","mcpHealth":{"checkedAt":"2026-10-26T00:00:00Z","result":{"success":true,"stage":"tools","reason":"ok"}},"mcp":{"recording":false,"dropped":1,"entries":[{"time":"2026-10-26T00:00:00Z","process":1,"parent":10,"event":"toolsListReplied"},{"time":"2026-10-26T00:00:01Z","process":1,"parent":10,"event":"inputEOF"},{"time":"2026-10-26T00:00:02Z","process":2,"parent":10,"event":"outputError","errorNumber":32}]},"mcpSecurity":{"checkedAt":"2026-10-26T00:00:00Z","executableExists":true,"executableAllowed":true,"quarantine":true,"signatureExit":0,"gatekeeperExit":3}}"#.utf8)
    let english = try CodexDiagnosticSummary.document(fixture, language: .english)
    checkTrue(english.contains("Result: Passed"))
    checkTrue(english.contains("normal client shutdown"))
    checkTrue(english.contains("Writing the local output pipe failed"))
    checkTrue(english.contains("not a fault conclusion"))
    checkTrue(english.contains("Older events were dropped"))
    let chinese = try CodexDiagnosticSummary.document(fixture, language: .chinese)
    checkTrue(chinese.contains("结果：通过")); checkTrue(chinese.contains("PID 2"))
    checkTrue(chinese.contains("不单独判为故障")); checkTrue(chinese.contains("不是故障结论"))
    let encoded = try JSONEncoder().encode(failed)
    checkEqual(try JSONDecoder().decode(CodexMCPHealthCheck.Result.self, from: encoded).reason, "host_exited")
}
