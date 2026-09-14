# MyTerm 1.6（Build 125）

- 新增 Codex 只读 MCP 接入，可读取授权 SSH 标签的近期输出、当前屏幕和选中文本，无需保存或下载日志。共享默认关闭，每次启动需重新授权。
- 新增独立的 Codex HTTP／SOCKS5 代理设置，支持代理认证。配置、密码存储及进程环境与 SSH 代理隔离；修改设置仅影响之后启动的 Codex 进程。
- 支持启动本地 Codex 标签、设备码登录，以及配置外部 Codex 的 MyTerm MCP。外部 IDE 和浏览器的代理需要单独配置。
- 提供有大小限制的增量读取、授权撤销和中英文可滚动设置窗口；保留原有六个设置标签。

需要另行安装 Codex CLI。Codex 代理密码保存在独立的应用本地加密存储中，第一版偏好备份不包含此密码库。详见仓库 docs/CODEX-INTEGRATION.md。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
