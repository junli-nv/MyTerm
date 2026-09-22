> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.2)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.2).

# MyTerm 1.6.2（Build 127）

- 启动 Codex 分析前检查已有登录；需要认证时，登录成功后自动继续原先选定的 SSH 分析任务。
- 普通登录按钮复用已有凭据，增加检查登录状态与主动重新登录入口。状态检查、登录和分析统一使用 Codex 文件凭据存储，不修改全局配置。
- Codex 退出后保留标签、输出和退出码，不再沿用本地 Bash 的自动关闭逻辑。分析界面使用普通屏幕保留诊断信息。
- 增加真实 PTY 登录到分析的衔接检查，以及默认不监控、退出诊断和中英文界面回归检查。

本地登录状态不代表服务端凭据一定有效，撤销或切换账号时可主动重新登录。SSH 与普通本地 shell 的退出行为保持不变。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
