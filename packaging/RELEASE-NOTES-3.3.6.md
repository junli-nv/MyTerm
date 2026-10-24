# MyTerm 3.3.6

## 简体中文

- 命令输出分页从 2 KiB 增加到 16 KiB，减少大输出的工具调用次数；保留 UTF-8 边界与完整读取校验。

- 无新输出时状态查询最多等待 20 秒，减少 Codex 的空轮询记录；不阻塞应用审批和取消。

- Codex SSH 执行工具默认精简返回内容，避免反复回显完整命令、原因和授权说明；保留完整输出、分页、错误与当前审批模式。
- 显式指定 `verbose=true` 可查看详细元数据；通过 `command_status` 查看已有任务，无需重新执行。
- Codex 自己显示的工具名称及调用参数仍由 Codex 控制。

## English

- Command output pages increase from 2 KiB to 16 KiB to reduce calls for large results, preserving UTF-8 boundaries and complete-delivery checks.

- Status queries wait up to 20 seconds when no output is available, reducing empty Codex polling without blocking app approval or cancellation.

- Compact Codex SSH execution replies omit repeated commands, reasons and authorization prose while preserving full output, pagination, errors and current approval mode.
- Explicit `verbose=true` requests detailed metadata; inspect existing jobs with `command_status` without rerunning commands.
- Tool names and arguments displayed by Codex remain controlled by Codex.
