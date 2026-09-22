> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.11)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.11).

## MyTerm 1.6.11（Build 136）

- SSH 启动依赖有效的 Codex 路径与代理格式；错误时给出返回配置入口。登录自动检查并可完成后继续分析，代理测试不作为硬性前提。配置修改使相关旧检查结果失效，已运行标签保持不变。
- Codex 接入页面拆分为两个固定标签：Codex 配置（CLI、代理、账号登录及外部 MCP 注册）和 SSH 会话接入（启动分析、访问授权和执行控制）。
- 登录检查与代理测试分别显示独立的进度和结果，位于对应按钮旁；两种结果不会互相覆盖，切换标签后保留。
- 登录状态明确区分尚未检查、已检测到本地凭据、未登录及检查失败；登录标签结束后更新状态。
- 小窗口内容可滚动、长说明自动换行，中英文切换保留所选标签；新增状态隔离、代理失败及两页布局检查。

登录检查针对本地凭据；代理 HTTPS 测试不代表模型请求一定可用。SSH 与 Codex 代理保持独立。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
