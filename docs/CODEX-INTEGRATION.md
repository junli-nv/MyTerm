# Codex 只读接入

MyTerm 1.6 开始提供第一版 Codex 只读接入。

## 使用

1. 安装 Codex CLI，在 **MyTerm → Codex 接入…** 中填写可执行文件路径（默认 `~/.local/bin/codex`）。
2. 打开需要分析的 SSH 标签，开启本机只读共享，仅勾选需要开放的标签。每次启动 MyTerm 默认关闭共享，授权不保存。
3. 配置 Codex 的 HTTP 或 SOCKS5 代理。可填写代理用户名和密码，点击“测试代理 HTTPS 连接”。该测试只验证 HTTPS 链路；登录及模型可用性需在 Codex 中确认。
4. 点击“登录 Codex”进行设备码登录，或使用已有的 Codex 登录状态。浏览器的代理须单独设置。
5. 点击“启动 Codex 标签”，可输入：`用 MyTerm 的工具列出开放的 SSH 会话，读取目标会话最近 200 行并分析错误。`

也可以点击“配置外部 Codex 的 MyTerm MCP”。这会执行 `codex mcp add myterm -- <当前 MyTerm 可执行文件> --myterm-mcp`，更新当前用户的 Codex 配置。重启外部 Codex 或 IDE 后生效。应用移动到新位置后，需要重新配置；建议在安装到 `/Applications/MyTerm.app` 后操作。

关闭接入窗口不会停止共享；关闭共享开关、关闭对应 SSH 标签或退出 MyTerm 才撤销读取权限。已经发送到 Codex 的输出无法撤回。读取内容由 Codex 按其当前模型及服务配置处理。

## 两套代理互相独立

- SSH 继续使用每个服务器、跳板机配置中的 `NetworkProxy` 和原有 `MyTermProxy`。
- Codex 配置单独保存在 `codex.connection`，仅通过专用环境传给新建的 Codex 进程，不修改 MyTerm 主进程环境、SSH 配置、系统代理或 `~/.ssh/config`。
- HTTP 代理直接用于 Codex；SOCKS5 通过专用的本地 HTTP CONNECT → SOCKS5 转换通道供 Codex 使用，避免依赖不同 Codex 版本的原生 SOCKS 支持。
- 转换通道仅监听 `127.0.0.1` 的随机端口，需要随机代理认证，最多 32 个连接，握手超时 15 秒。域名交给 SOCKS5 服务端解析。没有直连重试分支。
- 每个 Codex 标签持有其自己的代理通道。修改设置只影响之后启动的 Codex，不改变已运行的 Codex 或 SSH 会话。
- 代理密码保存在独立的应用本地加密存储 `MyTerm/CodexCredentials`，不使用系统钥匙串，不写入 SSH 密码库。第一版偏好备份不包含此独立密码库，恢复后需重新输入代理密码。
- 外部 IDE/Codex 进程不受 MyTerm 的 Codex 代理设置控制，需要自行配置。

## 工具与边界

- `list_sessions`：仅返回已开放的 SSH 标签，最多 32 项。不返回密码、密钥或 SSH 配置内容。
- `read_output(session_id, view, max_lines, max_bytes, cursor)`：`view` 可选 `history`（普通终端缓冲区）、`screen`（当前可见画面）和 `selection`（选中文本）。默认 200 行，最多 1000 行／8 KB。
- 响应包含 `cursor`、`reset`、`unchanged`、`truncated`、连接及全屏状态。传入上一轮 cursor 可以获取追加内容。重绘、重排、截断、授权变化或游标缓存淘汰后，`reset=true` 表示用完整新快照替换旧内容，不能直接拼接。
- 只在请求时提取文本，使用现有终端渲染后的文字与逻辑折行信息。不旁路读取 PTY、不改变终端尺寸或光标、不触碰 ZMODEM/trzsz 的数据流，也不要求开启日志保存。
- tmux/less 只提供普通缓冲区与当前画面，无法恢复已从 MyTerm 缓冲区移除、或远端程序从未显示过的内容。
- 本地 MCP 使用标准输入输出，经同用户认证的 Unix socket 访问应用。描述文件权限 0600；关闭共享会撤销发现信息、授权和快照缓存。请求有大小和速率限制。
- 终端输出视为不可信数据。MCP 只提供读取工具，没有命令执行、键盘输入、文件写入或凭据管理工具。外部 Codex 自身已有的工具权限仍由其配置控制。

## 验证

- `scripts/check.sh`：MCP 协议、代理 URL／认证编码、双向配置隔离及增量游标。
- `scripts/window-controls-check.py <MyTerm.app>`：真实 stdio MCP→私有 socket→模拟 SSH 终端；会话授权与撤销、全屏／历史读取、大小限制，以及中英文可滚动界面。原有六个设置标签页仍执行完整切换检查。
- `scripts/codex-proxy-check.py`：使用本机 Codex CLI、隔离的虚构 HTTPS 地址和无效测试密钥，忽略用户 Codex 配置且不保存线程。验证 HTTP 与 SOCKS5 的实际代理请求、认证、域名转发、二进制回环，以及同时运行时 SSH 原有代理仍使用独立地址。需要先构建 Debug 的 `MyTermChecks` 和 `MyTermProxy`。

参考：[Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

## 会话选择与持续监控（1.6.1）

点击“启动 Codex 标签”后，先在选择框中选择一个已打开的 SSH 标签。“确认并启动”会授权该标签，并将目标 ID 作为启动提示词传给 Codex，自动读取一次并等待后续问题。取消不改变授权，也不启动 Codex。

**持续监控默认关闭，每次启动重新选择，不记住上次的勾选。** 只有勾选“持续监控新输出”并确认启动，才会请求 Codex 循环等待和分析新输出。监控会消耗模型额度，即使长时间没有变化，等待超时后的工具往返也可能消耗额度。

接入设置中每个允许监控的标签有“停止监控”按钮。停止监控不会关闭 SSH；关闭共享、撤销该标签授权、关闭 SSH 标签或检测到 SSH 断开也会停止后续监控读取。关闭监控后仍可手动请求单次读取；要完全停止读取请撤销共享。Codex 已收到的数据不能撤回。

新增 `watch_output` 工具：每次在本地辅助进程中等待最多 20 秒，每 2 秒探测一次；有变化才返回内容，超时返回 unchanged，继续调用由 Codex 的当前任务负责。`view=auto` 在普通历史与 tmux/less 当前画面之间切换，重绘后使用完整快照替换，仍限制 1000 行／8 KB。不会在 UI 线程等待，也不会开启日志或积累无限队列。

这是交互式 Codex 任务中的持续分析，不是无人值守告警服务。Codex 被中断、任务结束、网络或额度限制均可能使分析停止；设置中的“已允许持续监控”表示读取权限，不代表模型仍在运行。需要时重新启动并勾选持续监控。

### 更完整的历史读取

1.6.1 在接入设置与启动选择框中提供历史行数（500／1000／2000／5000／10000）及总容量（64 KB／256 KB／1 MB）。默认最近 2000 个终端显示行、最多 256 KB。行数和容量任一达到上限即截断；折行合并仍沿用终端逻辑。需要先确保终端本身的滚动历史足够大，已经移出的内容无法恢复。

`capture_history` 冻结所选范围，返回分页游标；`read_history_page` 每页最多 4000 字节，持续读取直到 next_cursor=null。不会因 SSH 同时刷屏而在分页之间漏行或重复。最多保留 4 份、每份 1 MB 的内存快照，撤销共享即清空。启动提示词要求 Codex 读完全部页面再下结论；仍受模型上下文和额度限制。

### MyTerm 读取免重复审批

1.6.1 由 MyTerm 启动 Codex 时，将 MyTerm MCP 标记为 required，并仅为 list_sessions、read_output、watch_output、capture_history、read_history_page 设置 approval_mode=approve。启动提示词要求直接调用 MCP，连接失败时报错停止，不使用 printf 管道回退。不会修改全局命令审批策略，也不会写入宽泛的 printf 免审批规则。已经运行的旧 Codex 标签需要重新启动；外部 IDE 的审批配置不受这组启动参数控制。

配置依据：[OpenAI MCP 配置文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。
