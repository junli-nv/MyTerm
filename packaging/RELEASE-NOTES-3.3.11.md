# MyTerm 3.3.11

## 简体中文

- Codex 配置新增 SSH MCP 接口检查，实际启动辅助进程验证握手及工具发现，显示时间与失败阶段。包含可执行权限、下载隔离标记、签名和 Gatekeeper 只读评估；同步中英文系统权限说明。

- SSH 接入自动提供默认项目，无需先手动创建集群；仍可使用已有集群。

- “帮助 → 终端诊断”现在同时记录 MCP 辅助进程启动、初始化、工具发现、输入 EOF、输入上限和通信错误码，随 ZIP 导出。
- 默认关闭，共用 15 分钟窗口，最多 256 条 MCP 事件；私有本机文件可在重启后导出，清除或新记录会覆盖。无命令、输出正文、密码或令牌。
- 管道写入处理部分写入和中断，关闭的输出管道可记录错误而非静默 SIGPIPE 退出。
- 本地独立 Codex 不依赖 SSH MCP；本功能帮助定位 SSH 接入握手失败，不代表已修复尚未复现的故障。进程未启动或遭强制终止可能没有退出记录。

## English

- Codex settings add an SSH MCP interface check that starts the helper and verifies handshake/tool discovery, with a timestamp and failure stage. Includes read-only executable-access, quarantine, signature and Gatekeeper assessments plus bilingual permission guidance.

- SSH setup provides a default project without requiring manual cluster creation; existing clusters remain available.

- Help → Terminal Diagnostics now captures MCP helper startup, initialization, tool discovery, stdin EOF, input limits and pipe error numbers in exported ZIPs.
- Off by default, bounded to 256 MCP events within a 15-minute window. Owner-only local metadata survives restart; clear or a new capture replaces it. No commands, output text, passwords or tokens.
- Pipe writes handle partial writes and interruptions; a closed output pipe can be diagnosed instead of silently terminating through SIGPIPE.
- Standalone local Codex does not depend on SSH MCP. These diagnostics help investigate SSH MCP handshake failures; they do not claim a fix for the unreproduced incident. Failed launches or forced termination may leave no exit event.
