# MyTerm 3.0

Build 145 · Apple Silicon (arm64) · macOS 14 or later

## 中文

- “关于 MyTerm”和中英文 README 增加作者 Junli Zhang 与 GitHub 主页。
- 修复保留退出画面的标签继续占用 PTY 的问题。退出通知在末尾输出交付与子进程回收之后发送；隔离重连的旧回调，并防止向已回收 PID 发送信号。
- 关闭标签后按队列顺序清理日志权限、去重缓存和删除标记，保留已保存日志。
- 增加全局历史内存估算预算，默认 256 MiB，所有标签均分；可设为 0 仅按行数限制。预算不包含当前屏幕、图片和界面，不是进程总内存上限。打开标签、加宽窗口和降低预算可能淘汰最旧回看内容。
- 移除 Codex 持续监控入口和自动轮询工具；旧客户端收到已停止响应。
- Codex 接入默认等待任务，不主动分析已有 SSH 历史；增加默认关闭的“接入时读取已有输出”选项。后续命令仍要求读取完整输出。
- 中英文文档补充 Codex Scrollback 模式与无需 Shift 的终端选择说明。

## English

- Add author Junli Zhang and GitHub profile to About MyTerm and both README languages.
- Release PTYs for retained exited tabs after draining output; notify exit after output delivery and child reaping. Isolate stale reconnect callbacks and avoid signalling reaped PIDs.
- Release per-session logging permissions, deduplication caches and deletion markers after queued work completes, preserving saved logs.
- Add a global estimated scrollback memory budget, defaulting to 256 MiB shared across tabs; 0 uses only line limits. Visible screens, images and UI are excluded. This is not a process memory cap; opening tabs, widening windows and lowering the budget may discard oldest scrollback.
- Remove continuous monitoring and its polling tool; older clients receive a stopped response.
- Codex startup waits for a task by default. Initial SSH history analysis is opt-in; subsequent executed commands still require complete output delivery.
- Document Codex Scrollback mode and native selection without Shift in both README languages.
