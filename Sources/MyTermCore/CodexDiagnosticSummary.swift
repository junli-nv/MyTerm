import Foundation

/// Interpret only structured observations. Never infer a root cause from an exit code alone.
public enum CodexDiagnosticSummary {
    public enum Language { case chinese, english }
    public struct Health: Codable {
        public let checkedAt: Date
        public let result: CodexMCPHealthCheck.Result
        public init(checkedAt: Date, result: CodexMCPHealthCheck.Result) {
            self.checkedAt = checkedAt; self.result = result
        }
    }
    private struct Report: Decodable {
        var captured: Date?
        var mcpHealth: Health?
        var mcp: CodexMCPDiagnosticLog.Snapshot?
        var mcpSecurity: CodexMCPSecurityCheck.Report?
    }
    private static func text(_ zh: String, _ en: String, _ language: Language) -> String { language == .english ? en : zh }
    public static func explanation(_ result: CodexMCPHealthCheck.Result, language: Language) -> String {
        func t(_ zh: String, _ en: String) -> String { text(zh, en, language) }
        let stage: String
        switch result.stage {
        case .launch: stage = t("启动辅助进程", "Helper startup")
        case .initialize: stage = t("MCP 初始化握手", "MCP initialization handshake")
        case .tools: stage = t("获取工具列表", "Tool discovery")
        }
        let observation: String, action: String, certainty: String
        if result.success {
            observation = t("本次辅助进程启动、初始化和工具发现成功。", "Helper startup, initialization and tool discovery succeeded in this check.")
            action = t("若 Codex 仍报错，请开始诊断记录，重现问题并附上 Codex 原始错误和发生时间。", "If Codex still fails, start a diagnostic capture, reproduce the problem and include the original Codex error and incident time.")
            certainty = t("仅确认本次检查通过，不证明间歇故障已解决，也不验证 SSH 授权或远端连通性。", "This check passed; it does not prove intermittent failures are resolved or verify SSH authorization or remote connectivity.")
        } else {
            switch result.reason {
            case "permission_denied":
                observation = t("辅助程序缺少执行权限，或启动时收到权限拒绝。", "The helper is not executable or its launch was denied for insufficient permissions.")
                action = t("核对安装位置和系统弹窗中的程序名，必要时重新安装可信安装包；不要盲目开启全部隐私权限。", "Check the installed location and program named in any system prompt; reinstall a trusted package if needed. Do not grant all privacy permissions indiscriminately.")
                certainty = t("已确认权限拒绝，但尚不能确定是文件权限、系统策略还是其他限制；不等于已确认 Gatekeeper 拦截。", "Permission denial is confirmed, but file permissions, system policy or another restriction are not distinguished. Gatekeeper blocking is not established.")
            case "launch_failed":
                observation = t("未能启动辅助进程，尚未进入 MCP 握手。", "The helper could not be launched; the MCP handshake was not reached.")
                action = t("确认 MyTerm 安装完整并从“应用程序”启动；附上系统提示与诊断包。", "Verify the MyTerm installation and launch it from Applications; include system prompts and the diagnostic archive.")
                certainty = t("现有错误不足以确定根因，不能仅凭错误码判断是权限问题。", "The available error does not establish a root cause; its code alone does not prove a permission problem.")
            case "host_exited":
                observation = t("辅助进程在当前阶段退出或关闭了输出管道，未返回预期回复。", "The helper exited or closed its output pipe at this stage without the expected reply.")
                action = t("附上同一时间的 Codex 错误与诊断记录，交给维护者分析；不要反复重新授权 SSH。", "Provide the matching Codex error and diagnostic capture to the maintainer; repeatedly reauthorizing SSH is not a remedy for this observation.")
                certainty = t("退出或通信关闭已观察到；为什么退出仍未知，未证实是权限或 SSH 网络问题。", "Exit or communication closure was observed; its cause is unknown. A permission or SSH network cause is not established.")
            case "timeout":
                observation = t("当前阶段在检查时限内没有完成。", "This stage did not complete within the check deadline.")
                action = t("重试一次；仍失败则记录并导出诊断包，注明当时系统是否繁忙或有弹窗等待处理。", "Retry once; if it still fails, capture and export diagnostics, noting whether the system was busy or a prompt was waiting.")
                certainty = t("已确认检查超时；不能据此认定 SSH 断线或权限被拒绝。", "A check timeout is confirmed; it does not establish SSH disconnection or permission denial.")
            case "invalid_reply", "reply_limit":
                observation = result.reason == "invalid_reply" ? t("收到的回复不符合预期的 MCP 协议。", "The reply did not match the expected MCP protocol.") : t("回复超过检查器的容量上限。", "The reply exceeded the checker's capacity limit.")
                action = t("确认使用同一份最新 MyTerm，附上 Codex 版本和诊断包供维护者检查通信兼容性。", "Confirm the same current MyTerm copy is in use and provide the Codex version and diagnostic archive for compatibility analysis.")
                certainty = t("已确认回复异常，但具体来源仍需排查。", "An unexpected reply is confirmed, but its source needs investigation.")
            case "read_failed", "write_failed":
                observation = t("本机 MCP 通信管道读写失败。", "A local MCP communication pipe could not be read or written.")
                action = t("记录问题后重新打开 Codex 标签；仍失败则提交诊断包和错误原文。", "Capture the incident, then reopen the Codex tab. If it persists, provide the archive and original error.")
                certainty = t("这是本机通信失败，不能单凭管道错误确定是远端 SSH 故障。", "This is a local communication failure; a pipe error alone does not establish a remote SSH failure.")
            default:
                observation = t("检查未完成，现有记录无法解释此结果。", "The check did not complete and the available record cannot explain this result.")
                action = t("请提供诊断包、问题时间及 Codex 错误原文。", "Provide the diagnostic archive, incident time and original Codex error.")
                certainty = t("根因未知。", "Root cause unknown.")
            }
        }
        let impact = result.success ? t("本次检查可获取 MyTerm 工具列表。", "This check can obtain the MyTerm tool list.") : t("本次检查未能完成工具发现；检查没有读取 SSH 输出或执行远端命令。", "This check could not complete tool discovery; it read no SSH output and ran no remote commands.")
        return [t("阶段：", "Stage: ") + stage, t("观察：", "Observation: ") + observation,
                t("影响：", "Impact: ") + impact, t("建议：", "Next step: ") + action,
                t("判断边界：", "What is established: ") + certainty].joined(separator: "\n")
    }
    public static func document(_ data: Data, language: Language) throws -> String {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(Report.self, from: data)
        func t(_ zh: String, _ en: String) -> String { text(zh, en, language) }
        let date = ISO8601DateFormatter()
        var lines = [t("MyTerm 诊断摘要", "MyTerm diagnostic summary")]
        if let captured = report.captured { lines.append(t("导出时间：", "Exported: ") + date.string(from: captured)) }
        if let health = report.mcpHealth {
            lines += ["", t("最近一次主动接口检查", "Most recent explicit interface check"),
                      t("检查时间：", "Checked: ") + date.string(from: health.checkedAt),
                      t("结果：", "Result: ") + (health.result.success ? t("通过", "Passed") : t("未通过", "Failed")),
                      explanation(health.result, language: language)]
        } else {
            lines += ["", t("尚无主动接口检查结果。请在 Codex 配置中点击“检查 SSH MCP 接口”，再导出诊断包。", "No explicit interface check is available. Use Check SSH MCP interface in Codex configuration, then export again.")]
        }
        lines += ["", t("MCP 事件记录（与上述检查可能不是同一次连接）", "MCP event capture (may concern different connections from the check above)")]
        if let snapshot = report.mcp, !snapshot.entries.isEmpty {
            if snapshot.dropped > 0 { lines.append(t("部分旧事件已被容量限制覆盖，不能重建完整过程。", "Older events were dropped by the capacity limit; the complete sequence cannot be reconstructed.")) }
            let processes = Dictionary(grouping: snapshot.entries, by: { $0.process })
            for pid in processes.keys.sorted() {
                guard let events = processes[pid], let last = events.last else { continue }
                lines.append("PID \(pid) · " + date.string(from: last.time))
                let problems = events.filter { [.parseError, .inputError, .inputLimit, .outputError].contains($0.event) }
                if !problems.isEmpty {
                    for entry in problems.suffix(4) {
                        let meaning: String
                        switch entry.event {
                        case .parseError: meaning = t("收到无法解析的协议消息。", "An unparseable protocol message was received.")
                        case .inputLimit: meaning = t("输入超过容量上限，辅助进程停止处理。", "Input exceeded the capacity limit; the helper stopped processing.")
                        case .inputError: meaning = t("读取本机输入管道失败。", "Reading the local input pipe failed.")
                        default: meaning = t("写入本机输出管道失败；对端关闭是可能原因之一。", "Writing the local output pipe failed; peer closure is one possible cause.")
                        }
                        lines.append(date.string(from: entry.time) + " · " + meaning)
                    }
                }
                if events.contains(where: { $0.event == .toolsListReplied }) {
                    lines.append(t("记录中曾成功返回工具列表；不代表整个使用期间无故障。", "A tool list was returned during this capture; this does not establish an error-free session."))
                } else {
                    lines.append(t("记录未包含完整工具发现。可能未记录到全部阶段，不能仅据此判断进程崩溃。", "The capture lacks complete tool discovery. Stages may not have been captured; this alone does not prove a crash."))
                }
                if last.event == .inputEOF { lines.append(t("最后收到输入结束；客户端正常关闭也会产生此事件，不单独判为故障。", "Input ended last; normal client shutdown also causes this event, so it is not classified as a fault on its own.")) }
            }
        } else {
            lines.append(t("没有 MCP 事件。请先开始新记录，再重现问题并导出；没有事件不等于没有故障。", "No MCP events were captured. Start a new recording, reproduce and export; absence of events does not establish absence of a fault."))
        }
        if let security = report.mcpSecurity, let code = security.gatekeeperExit, code != 0 {
            lines += ["", t("排查线索（不是故障结论）：Gatekeeper 评估未通过。临时签名应用即使已获用户放行也可能出现此结果，不能据此认定 MCP 被拦截。", "Investigative clue, not a fault conclusion: Gatekeeper assessment did not pass. An ad-hoc app with a user exception may still produce this result; it does not prove MCP was blocked.")]
        }
        lines += ["", t("请附上问题发生时间、复现步骤及 Codex 错误原文。原始阶段、事件和数字错误码保存在 diagnostic.json，供维护者进一步分析。摘要仅解释现有元数据，不分析终端正文，也不猜测缺失信息。", "Include the incident time, reproduction steps and original Codex error. Raw stages, events and numeric codes remain in diagnostic.json for maintainers. This summary interprets existing metadata only; it does not analyze terminal contents or invent missing evidence.")]
        return lines.joined(separator: "\n") + "\n"
    }
}
