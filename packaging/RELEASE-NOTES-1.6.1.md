> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.1)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.1).

# MyTerm 1.6.1（Build 126）

- 新增 Codex 只读 MCP 接入：按 SSH 标签授权读取输出，无需保存或下载日志。共享每次启动默认关闭。
- Codex 支持独立的 HTTP／SOCKS5 代理及认证，与 SSH 的配置、密码存储和进程环境隔离。
- 启动 Codex 前选择 SSH 标签，自动分析所选历史。持续监控默认关闭，每次需主动勾选，可停止监控或撤销共享。
- 历史范围可设置为 500–10000 行、64 KB–1 MB，默认 2000 行／256 KB。冻结快照并分页读取，避免只取末尾 8 KB 或刷屏造成分页漏行；达到总上限明确提示截断。
- MyTerm 启动的 Codex 对五个只读 MCP 工具配置免重复审批，并要求直接调用 MCP；不修改全局本地命令审批。
- 完善中英文可滚动的会话选择与接入设置界面，保留原有六个设置标签。

需要另行安装 Codex CLI。持续监控会使用模型额度，任务停止后需重新启动，不是无人值守告警服务。无法恢复已从终端缓冲区移出的历史。外部 IDE／浏览器代理需单独配置；独立 Codex 代理密码库暂不包含在偏好备份中。

验证包括 Debug、Release、实际 DMG 副本及安装后完整界面检查、核心检查与应用内容一致性校验。完整历史说明见随 Release 提供的 CHANGELOG.md。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
