# MyTerm 3.3.12

## 简体中文

- 标签和分屏菜单统一使用“编辑标签…”修改名称、颜色与环境标识；保留当前标签名称与共享 SSH 标识的不同保存范围，取消或验证失败不部分保存。

- MCP 状态页仅显示实际启动、初始化和工具发现结果；实际启动权限不足时提供明确提示。
- 签名、隔离标记和 Gatekeeper 评估保留在诊断包，不再作为常驻界面提示；评估结果不影响 MCP 成功判定。
- SSH 会话接入移除重复的 Codex 依赖说明及登录状态；配置无效时仍显示原因和返回配置按钮，启动前校验与自动登录流程保留。
- 同步中英文文档及界面翻译。

## English

- Tab and split-pane menus use one Edit Tab dialog for name, color and environment. Current-tab names and shared SSH identification retain their distinct persistence scope; cancel or validation failure does not partially save.

- MCP status shows actual startup, initialization and tool discovery results, with a clear message when helper launch is denied for insufficient permissions.
- Signature, quarantine and Gatekeeper assessments remain in diagnostic archives rather than persistent UI notices; assessments do not affect MCP success classification.
- SSH access removes duplicate Codex dependency descriptions and login status. Invalid configuration still shows its reason and a return button; startup validation and automatic login remain enabled.
- Matching Chinese/English documentation and localization.
