> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.4)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.4).

# MyTerm 1.6.4（Build 129）

- 新增按 SSH 标签明确授权的 Codex 命令执行，默认仍为只读。复用已认证 SSH 连接上的独立非交互通道，与 Codex 代理隔离，不共享终端目录、环境变量或 tmux 状态。
- 执行前确认计划默认开启，可在启动选项中关闭。授权后固定诊断清单内的命令自动执行，其他命令显示完整内容和理由，须逐条确认。
- 命令输出按任务 ID 和偏移分页读取；未读完上一条输出或跳过分页时不允许继续执行。输出超限、取消或超时明确标记不完整并停止自动推进。
- 每次授权最多 10 分钟、30 条命令；单条最多 60 秒和 1 MB 输出。支持停止和撤权，断线、重连或关闭拥有执行权限的 Codex 标签后撤权。停止通道不能保证终止远端已脱离会话的后台进程。
- 新增中英文可滚动执行控制窗口，保留命令、状态及输出预览；记录仅在内存中保留。
- 增加真实本地 SSH 连接复用执行、默认权限、计划确认开关、输出完整性和撤权检查，并纳入发布验证。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
