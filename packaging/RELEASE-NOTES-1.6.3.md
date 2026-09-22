> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.3)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.3).

# MyTerm 1.6.3（Build 128）

- 修复 Codex MCP 启动路径错误：Foundation 的 JSON 编码将路径斜杠转义为 TOML 不接受的形式，导致 required MCP 初始化报 No such file or directory，Codex 随后以 exit=1 退出。
- 保留路径中的普通斜杠，同时正确处理空格、引号和 Unicode。
- 外部 MCP 注册状态、实际路径和最近检查时间直接可见，配置后自动回读验证。
- Codex 退出时针对 MCP 路径、服务初始化、登录凭据、网络和配置错误给出具体处理提示，保留原始报错。
- 安装包验证新增真实 Codex CLI 解析生产启动参数，并使用解析结果启动 MCP、验证初始化和五个只读工具。Debug、Release、DMG 副本和安装版均执行此检查，无需调用模型。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
