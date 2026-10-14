# MyTerm

简体中文 · [English](README.en.md)

作者：Junli Zhang · [GitHub](https://github.com/junli-nv)

[GitHub 仓库](https://github.com/junli-nv/MyTerm) · [下载安装包](https://github.com/junli-nv/MyTerm/releases/latest) · [历史更新日志](CHANGELOG.md)

macOS 原生 SSH 工作台，使用 SwiftUI / AppKit 管理界面、SwiftTerm 提供终端、系统 OpenSSH 负责认证和连接。支持本地 Bash、多标签 SSH、会话分组、文件传输，以及本地 Codex 启动和按 SSH 会话授权的 Codex 接入。

## 安装与构建

从 [最新 Release](https://github.com/junli-nv/MyTerm/releases/latest) 下载适合设备架构的 DMG，打开后将 MyTerm 拖入“应用程序”。版本、构建号与附件校验值以 Release 页面和 `SHA256SUMS.txt` 为准。发布包使用临时签名（ad-hoc），未进行 Developer ID 签名与 Apple 公证。

### 从零安装 MyTerm

MyTerm 应用要求 macOS 14 或更高版本。先在“关于本机”确认芯片：Apple Silicon（M 系列）选择 `arm64` 包；Intel 只能使用对应架构的包或自行构建，不能直接使用 arm64 包。可下载架构以 Release 附件为准。

| 要使用的功能 | 本机需要准备什么 |
| --- | --- |
| 本地 Bash、SSH、SFTP | MyTerm 安装包；使用 macOS 自带的 Bash/OpenSSH/SFTP，无需先装 Homebrew 或 Codex |
| Codex 本地工作、SSH 分析 | 提前安装 Codex CLI；下面使用 Homebrew 安装，因此先装 Homebrew |
| ZMODEM | 本机及远端的 `sz` / `rz`（本机可用 `brew install lrzsz`）；见下方传输说明 |
| trzsz / tmux 传输 | MyTerm 内置客户端，远端需安装 `trz` / `tsz`；见下方传输说明 |
| X11 转发 | 额外安装并运行 XQuartz，详见下文 X11 说明 |
| 源码构建和开发测试 | Swift/开发工具及测试依赖，见下方构建说明和[测试文档](docs/TESTING.md) |

1. 从[最新 Release](https://github.com/junli-nv/MyTerm/releases/latest)下载 DMG 和 `SHA256SUMS.txt`，不要使用来源不明的重新打包文件。
2. 在 macOS“终端”中进入下载目录，运行 `shasum -a 256 <下载的DMG文件路径>`（用实际路径替换占位符），将结果与校验文件中的对应条目比较。
3. 打开 DMG，将 MyTerm 拖到“应用程序”；推出 DMG，再从“应用程序”打开 MyTerm。
4. 首次进入显示开始页面，可新建本地 Bash 或 SSH 会话。Codex 并非启动 MyTerm 的必要条件。

### macOS 阻止首次打开时

发布包采用临时签名（ad-hoc），尚未进行 Developer ID 签名和 Apple 公证。因此首次打开可能提示无法验证开发者或无法检查恶意软件。确认下载来源和校验值后，先尝试打开一次，再到 **系统设置 → 隐私与安全性 → 安全性 → 仍要打开**，确认“打开”，并按系统要求认证。之后从“应用程序”启动即可。步骤依据 [Apple 官方说明](https://support.apple.com/en-us/102445)。

如果看不到“仍要打开”，先重新尝试启动；受组织管理的 Mac 可能需要管理员放行。如果提示文件损坏或会损害电脑，先核对校验值并重新下载，无法解决时反馈具体提示；不要直接关闭整个系统的 Gatekeeper。

### 安装 Homebrew 和 Codex CLI（使用 Codex 时）

已有 `brew` 和 `codex` 时可跳过安装，先用 `brew --version`、`codex --version` 检查。MyTerm 不会自动安装它们。

在系统“终端”中按 [Homebrew 官方安装说明](https://brew.sh/)运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

按安装程序提示完成操作和 **Next steps**。Homebrew 有独立的系统支持范围，可能高于 MyTerm 的最低要求，旧版 macOS 请先核对 [Homebrew 系统要求](https://docs.brew.sh/Installation)。如提示安装 Command Line Tools，按提示安装。Apple Silicon 默认安装到 `/opt/homebrew`；可在当前终端加载环境：

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
brew --version
```

让新终端也能找到 `brew`，需按安装程序的 Next steps 配置实际使用的 shell；Bash 示例使用 `~/.profile`。不要把 Apple Silicon 的路径套用到 Intel 或自定义安装目录。

安装 [Homebrew 的 Codex CLI 包](https://formulae.brew.sh/cask/codex)，并确认命令路径：

```bash
brew install --cask codex
command -v codex
codex --version
```

已有 Homebrew 安装的 Codex 可用 `brew upgrade --cask codex` 更新。CLI 的使用与登录方式见 [OpenAI 官方文档](https://learn.chatgpt.com/docs/codex/cli)。

打开 **MyTerm → Codex 接入… → Codex 配置**，填写 `command -v codex` 返回的完整路径。默认值为 `/opt/homebrew/bin/codex`；Intel Homebrew 通常为 `/usr/local/bin/codex`，其他安装方式以实际路径为准。已有自定义路径不会被默认值覆盖。

需要代理时，先在这里设置独立的 HTTP/SOCKS5 代理并测试，再点击登录、检查登录状态；该代理不会改变 SSH 自己的代理。MyTerm 中的代理仅供其启动的 Codex 使用，不能解决此前 Homebrew/CLI 下载阶段的网络问题，安装阶段需先确保终端能访问下载站点。登录成功后可选择“本地工作”，或先打开 SSH，再从“SSH 会话接入”启动分析。详细步骤见 [Codex 接入指南](docs/CODEX-INTEGRATION.md)。

### 从源码构建与打包

源码构建需要 macOS 14+、Swift 6.0+。在仓库根目录运行：

```bash
bash scripts/build-app.sh
open dist/MyTerm.app
```

默认生成当前 Mac 架构的 Debug 应用；`bash scripts/build-app.sh release` 生成优化构建。依赖源码和二进制随仓库提供，版本、补丁及第三方声明见 [SwiftTerm 补丁说明](vendor/SwiftTerm/MYTERM-PATCH.md) 和 [trzsz 说明](vendor/trzsz/1.2.0/README.md)。

发布与安装验证：

```bash
bash scripts/package-release.sh
bash scripts/create-dmg.sh
bash scripts/install-release.sh
```

版本由 [packaging/Info.plist](packaging/Info.plist) 定义，产物输出到 `dist/releases/<版本号>/`，包含 ZIP、DMG、发布说明与 SHA-256 校验文件。打包脚本会拒绝覆盖已有同版本目录。

发布流程对 Debug、Release、从 DMG 复制的应用执行窗口与功能检查，并核对应用包的文件、权限及符号链接。安装脚本从已验证 DMG 更新 `/Applications/MyTerm.app`，再次检查签名、内容和窗口行为，通过后打开安装版，并将 `dist/MyTerm.app` 同步为相同产物；安装验证失败时恢复原应用。

## SSH 连接

启动默认显示开始页面，不自动打开本地会话。可新建 SSH 配置，或双击侧栏中保存的服务器连接；单击不发起连接。SSH 编辑窗口支持缩放、最大化和滚动，底部保存操作保持可见。

- **认证**：自动、密码或密钥。自动沿用 OpenSSH 的认证选择；密码模式使用密码 / 键盘交互；密钥模式使用公钥认证，可选择私钥、SSH agent 或 SSH 配置中的密钥。
- **跳板机**：支持多级跳转，可逐级填写地址、端口、用户名、认证方式和私钥，并调整顺序。可提前填写可选密码（需指定用户名），留空则复用已有密码或连接时询问。“选择已有跳板配置”从已保存会话复制完整跳转路径及网络代理，支持多级跳转；修改副本不会改动来源。也可使用 SSH 配置中的跳板定义。
- **网络代理**：HTTP CONNECT 或 SOCKS5，支持无认证代理。可与跳板组合，代理应用到第一跳。
- **压缩**：默认开启，可按服务器关闭。
- **端口转发**：本地 `-L`、远程 `-R`、动态 SOCKS `-D`，支持多条规则，默认监听 `127.0.0.1`。点击“添加”新增规则，点击每条规则的“删除转发”移除；保存后从更新的配置新建 SSH 连接生效，已有连接不受影响。转发随 SSH 连接结束；监听失败时连接报错退出，远程监听范围受服务端配置约束。
- **连接调试**：可开启相当于 `ssh -vvv` 的调试输出，默认关闭。
- **保活**：使用 `ServerAliveInterval=30`、`ServerAliveCountMax=6` 和 `TCPKeepAlive=yes`。保活不能避免实际网络中断。

交互式 SSH 使用 `-e none`，让 `~.` 等按键传给远端 ipmitool 等控制台程序。退出 SSH 可输入 `exit` 或关闭标签。连接参数使用 `StrictHostKeyChecking=no`。

通过侧栏“导入 SSH 配置”或 `⌘⇧I` 按需导入 `~/.ssh/config` 的 Host 别名。支持普通 Include、文件通配符及递归防循环，跳过 Host 通配模式和重复别名；导入阶段不执行 Match exec，不展开 Include 中的环境变量和百分号 token。保存别名后，由 OpenSSH 在连接时读取实际配置。

### X11 转发

SSH 配置可选择关闭、普通转发（`-X`）或受信任转发（`-Y`），默认关闭；需在会话中显式开启。启用时需本机安装、运行 XQuartz，并由远端 sshd 允许 X11Forwarding。应用从环境或 launchctl 获取 DISPLAY，缺失时提示启动 XQuartz。受信任模式仅用于可信服务器。

## 标签与分组

按住标签标题拖到另一标签上，可调整 SSH、本地 Bash 和 Codex 标签的顺序，不重建连接或改变当前选中会话。单击即可选中标签，整个标签区域（包括留白）都可点击；右键或 Control+单击会先选中目标标签再打开菜单，无需先左键选中或双击。更改标签名称后，标题和宽度立即更新。右键标签可关闭、复制、更改名称、设置日志策略；SSH 标签还提供连接配置编辑和重新连接。复制标签会新建独立连接，不复制进程或历史。

标签栏右侧 `+` 和空白区域菜单提供本地会话、SSH 配置、已保存服务器及会话恢复入口。空白处双击最大化 / 还原窗口。左侧栏和底部状态栏可独立隐藏，底栏在新会话中默认收起。SSH 标签右上角 `+` 旁提供 SFTP 按钮，无需打开底栏。

常用快捷键：

| 快捷键 | 操作 |
| --- | --- |
| `⌘T` | 新建本地 Bash 会话 |
| `⌘N` | 添加服务器 |
| `⌘W` | 关闭当前标签 |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | 向后 / 向前循环切换标签 |
| `⌃⌘S` | 显示 / 隐藏侧栏 |
| `⌘⇧S` | 保存当前多标签会话 |
| `⌘⇧H` | 打开会话历史 |
| `⌘⇧E` | 导出当前会话文本 |
| `⌘,` | 打开设置 |

侧栏按“分组 → 会话”两层树展示，支持展开、折叠、重命名和删除分组。将未分组会话拖到另一个未分组会话上，会提示命名新分组；保存后同时加入两者，取消不改动数据。拖入已有分组可移动成员，拖到“未分组”标题或底部提示区可退出分组，右键“移至分组”也可操作。删除分组保留连接定义。搜索匹配分组名称、服务器名称、地址和用户名，并展开匹配项。

“保存与恢复会话”支持保存、恢复、重命名、更新和删除多标签记录，保留标签顺序、连接定义、选中标签及本地目录，最多 100 个标签。退出时保存“上次退出时的会话”。恢复会追加标签、重新建立连接，不恢复终端进程或将历史文本写回活动终端。远端程序需在断线后持续运行时，可使用 tmux。

本地 Bash 和 SSH 正常退出后自动关闭对应标签。SSH 异常断线保留输出，聚焦终端按 `R` / `r` 或点击“重新连接”可在原标签重连。本地 Bash 是交互式登录 shell，遵循 `~/.profile` 等启动文件规则；本地目录随 OSC 7 更新，未上报时保留初始目录。

## SFTP 文件管理

新建 SSH 标签即显示右上角 SFTP 入口，面板默认隐藏。完成 SSH 登录后，点击该入口展开面板，再点“连接”。SFTP 复用已认证的 SSH 连接，不重复询问密码；“断开”只结束 SFTP，不关闭 SSH 终端。

- 单击选择文件或目录，`Command` / `Shift` 多选；双击目录进入，路径栏可直接跳转。
- 工具栏或右键菜单提供下载，支持批量上传、下载及递归目录传输，包括空目录与隐藏文件。
- 从 Finder 拖入文件或目录，上传到面板当前目录；从列表拖到 Finder，下载所选项目。
- 面板右上角可弹出独立可缩放窗口，关闭或收回后回到内嵌面板，连接和选择状态保持。已弹出时，标签栏 SFTP 按钮将独立窗口置前。
- 传输按顺序执行，显示当前文件、进度及速度，遇错停止。取消会断开 SFTP 并保留续传文件。

目录重试会合并已有目录，并逐字节核对后跳过同内容文件。上传拒绝覆盖不同内容的同名文件；下载已有项目时，通过保存对话框或合并/覆盖提示确认。符号链接和特殊文件报错停止，不跟随链接。目录递归限制为 128 层、每个所选根项目 100,000 个条目。文件名使用 UTF-8。文件面板统一使用 SFTP，不提供 SCP 选项。

### 中断续传

中断或取消后，重新连接 SFTP，选择**相同源项目和目标路径**继续。上传使用远端 `.myterm-part` 文件及 JSON 元数据；下载使用本地 `.文件名.myterm-part` 及 JSON 元数据，完成后才提交最终文件。不要删除续传文件，也不要在传输或续传期间修改源文件。

上传校验源文件 SHA-256；下载续传验证连接标识、远端路径、大小和修改时间，不提供远端整文件哈希校验。元数据不匹配时拒绝续传。批量操作已完成的文件保留，修正错误后可重新选择未完成项目或重试目录。

速度按当前文件实际新增传输字节计算，不将断点前已完成的部分计入；定时更新并平滑显示，结束后显示平均速度。

## ZMODEM 与 trzsz

### ZMODEM

本机和远端需提供 `rz` / `sz`，本机可安装：

```bash
brew install lrzsz
```

应用查找 `/opt/homebrew/bin`、`/usr/local/bin` 和 `/usr/bin` 中的工具，不将 lrzsz 打包进应用。远端执行 `sz 文件名` 后选择本地接收目录，执行 `rz` 后选择本地发送文件。接收保护已有文件，发送请求续传，是否接受由远端接收器决定。状态栏显示进度、速度并可取消；速度包含协议开销与重传。

把普通文件拖到已登录的 SSH **终端区域**时，应用会清除尚未提交的命令行、执行传输命令并等待握手。请停留在普通 shell 提示符，不要在编辑器中拖入文件。远端缺少工具或握手超时会提示错误。终端区域拖放与 SFTP 面板拖放是不同入口。

### trzsz 与 tmux

SSH 默认启用内置 trzsz 客户端，远端需提供 [trzsz-go](https://github.com/trzsz/trzsz-go) 的 `trz` / `tsz`。在远端 shell 或 tmux 窗格执行 `trz` 上传、`tsz 文件名` 下载，目录使用 `trz -d` / `tsz -d 目录`；Ctrl+C 取消。

ZMODEM 不适用于 tmux。拖拽协议的自动模式在普通屏幕使用 ZMODEM，在备用屏幕使用 trzsz；也可在 SSH 配置中固定为 trzsz 或关闭 trzsz。备用屏幕检测不能区分 tmux 和 vim，拖拽前仍需回到 shell 提示符。修改配置后重新打开连接生效。

通过应用配置的 ProxyJump 可保持原跳转设置。若手动从中间机 tmux 再 SSH 到下一台机器，需在中间机安装 trzsz 客户端并使用 `trzsz --relay ssh 目标`。客户端沿用 `~/.trzsz.conf` 的选择目录等配置；协议在终端字符解码前处理，不受终端字符编码设置影响。

## Codex 接入

SSH 分析标签默认不会在启动时主动读取已有 SSH 输出。需要先分析历史时，在选择 SSH 会话的窗口勾选“接入时读取已有输出”；否则等待你的任务，从后续命令开始分析。应用仅在本地建立输出游标基线，不把初始快照发送给 Codex。此选项控制启动流程，不是历史访问权限隔离；之后仍可明确要求回溯历史。游标失效或终端快照截断须提示覆盖缺口；通过执行接口运行的命令仍须读取全部 `command_status` 分页，直到 `all_output_delivered=true`。

在 **MyTerm → Codex 接入…** 中通过三个纵向分类操作：**Codex 配置**管理 CLI、登录、代理与外部 MCP；**SSH 会话接入**管理 SSH 分析；**本地工作**直接启动本地 Codex。

点击“启动 Codex 标签”，选择已打开的 SSH 会话。默认勾选“允许执行 SSH 命令”，执行前逐条确认；取消勾选可保持只读。按任务需要读取输出，不提供自动后台监控；授权后仍可自主进行多步命令排查，也可按明确约定的间隔和次数执行定时检查。历史可配置读取范围并分页，已从终端缓冲区移除的内容无法补回，不需要为此开启磁盘日志。

确认启动时按所选项授予 SSH 执行权限，可调整授权时长和命令额度，到期后可在原标签续期。默认逐条确认，也可在 MyTerm 中切换“本会话始终允许”，并随时切回；撤销或授权到期后清除持续允许。计划仅由 Codex 在终端中展示，MyTerm 不捕获或重复展示；命令通过 MyTerm 的执行通道运行，须读取全部输出后再继续。执行通道不共享终端当前目录、环境或 tmux 状态。

Codex 的 HTTP / SOCKS5 代理与 SSH 代理独立。SSH 分析标签启动时自动携带目标会话 ID，无需手工复制；外部客户端通过 `list_sessions` 查询已授权会话。外部 MCP 适配器由启动它的 Codex/IDE 持有，通信管道关闭后退出；不应将其单纯驻留视为 MyTerm 主窗口仍在运行。

SSH 命令支持多行脚本（LF 换行、Tab 缩进，最多 4096 UTF-8 字节），整段作为一次命令审批。单条最多执行 60 秒、保留 1 MiB 输出。

同一个 SSH 标签可关联多个 Codex 标签，分别管理授权、额度、审批和输出读取进度。续期、停止或关闭一个 Codex 标签不影响其他标签；同一 SSH 上已批准的命令串行执行，排队时无需重新授权。关闭 SSH 或断线会使关联执行授权失效。外部 MCP 可读取已共享会话，不能复用内置标签的执行授权。

完整流程、排队状态和限制见 [Codex 接入说明](docs/CODEX-INTEGRATION.md)。

### 本地 Codex

在 **MyTerm → Codex 接入 → 本地工作** 确认或选择工作目录，点击 **启动本地 Codex** 即可。默认目录为用户主目录；无需先打开 Bash 或 SSH 标签，也不关联、读取其他标签的输出。

复用 **Codex 配置** 中的登录及 HTTP/SOCKS5 代理，不修改 `~/.profile`、普通 Bash 或 SSH 的代理。本地模式不启用 MyTerm MCP，不依赖外部 MCP 注册或终端共享。登录完成后自动继续启动，成功后关闭接入窗口。

本地命令与文件操作由 Codex 自身执行，使用 `workspace-write` 沙盒和 `on-request` 审批：所选工作目录允许写入，并非每条命令都需 MyTerm 确认。它不会继承其他 Bash 标签中的临时变量、别名或运行中的程序。SSH 分析仍通过“SSH 会话接入”选择目标并使用原有授权流程。

### Codex 显示与复制粘贴

希望保留问答排版，同时使用 MyTerm 的直接拖选复制时，在 Codex 的 TUI 模式选项中选择 **Scrollback**，退出后重新启动 Codex。该选项对应 `~/.codex/config.toml` 中的 `fullscreen_transcript = false`，与原始输出模式 `raw_output_mode` 不同：

```toml
[tui]
fullscreen_transcript = false
```

在 Codex CLI 0.157.1 的普通会话界面中，Scrollback 不开启鼠标报告：启用 MyTerm 的“选中文本后自动复制”后，直接拖选并松开鼠标即可复制，**无需 Shift**；启用“右键直接粘贴”后，右键仍直接粘贴。若使用 Fullscreen 模式或其他接管鼠标的界面，可按住 Shift 拖选，并保持到松开鼠标，以使用本地选择。`Shift + 右键` 显示菜单。

无需额外配置 `raw_output_mode` 或 `alternate_screen`：它们的默认值分别为 `false` 和 `"auto"`。若此前设置了 `raw_output_mode = true` 或 `alternate_screen = "never"`，请删除这些覆盖项或恢复默认值。Scrollback 不需要开启原始输出模式；原始输出模式可能削弱提问和回复的视觉区分。默认值与选项含义见 [Codex 官方配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)。

若已有 `[tui]` 段，请在原段内修改，不要重复声明，保留主题等其他配置。使用自定义 `CODEX_HOME` 时，应修改该目录中的 `config.toml`。保存后退出当前 Codex，再运行 `codex`；无需重启 MyTerm。MyTerm 内置 Codex 标签的启动参数可覆盖显示设置；这些选项不改变 SSH 执行授权。

## 终端显示与操作

**设置 → 语言** 支持中文、英文与跟随系统，切换立即生效，包括编辑和窗口菜单中的自动填充、居中等系统项目，无需重启。设置与 Codex 接入窗口使用左侧纵向分类导航，可调整窗口大小；右侧内容独立滚动。

**设置 → 主题与字体** 支持系统 / 深色 / 浅色界面、带色板预览的深浅主题预设、字体下拉选择和 **5–36 pt** 字号。安装字体后重新打开主题页面刷新列表；终端表格和 tmux 建议使用等宽字体。按住 Ctrl 在触摸板双指上滑放大、下滑缩小，每步 0.5 pt，忽略惯性滚动。终端获得焦点时，也可按 `⌘+`（或 `⌘=`）放大、`⌘-` 缩小，每次 0.5 pt；与触摸板缩放一样调整全局终端字体设置。

新增预设为夜空、北境、柔雾和暖奶油，各自包含完整 ANSI 16 色。色板卡片提供预览，点击才应用；保留当前字体、字号和背景透明度。配色参考 [TerminalColors 深色主题](https://terminalcolors.com/tags/dark/)和[浅色主题集合](https://gist.github.com/lr580/7ec84df732e0946f03504d7fe02387c0)，采用 MyTerm 自身调整后的颜色，并非原主题的逐色复刻。

可编辑文字、背景、光标、光标文字、选区背景/文字及 ANSI 16 色，支持系统调色器、HEX 输入、终端预览与 `.itermcolors` 导入导出。导入保留字体、字号和透明度；缺失颜色保持原值。背景不透明度默认 100%，仅影响默认背景与左右留白，不降低文字或程序指定背景色的透明度。ANSI 调色板不改写程序的 RGB 真彩色。

**设置 → 输出着色** 可为关键词设置颜色、优先级、整词匹配与大小写规则。默认对 SSH 普通屏幕的错误、成功、警告词分别标红、绿、黄，并保留远端 ANSI 颜色；本地终端与全屏程序可单独开启。着色只影响显示，不改变复制、导出或传输数据。终端左右保留空白，列数按实际可用宽度计算。

**设置 → 终端行为** 可调整选中自动复制、右键粘贴和终端响铃，默认启用选中复制、右键粘贴并禁用响铃。`Shift + 右键` 始终显示菜单，`⌘C` / `⌘V` 可用。

**设置 → 终端行为 → 全屏终端触摸板** 提供标准、快速（默认 4 倍）和按页模式。进入 tmux 复制模式（`Ctrl+B` 后按 `[`）后可用双指快速翻阅；选择“按页翻动”会按滑动方向发送 Page Up / Page Down，忽略惯性并限制翻页频率。终端无法可靠识别 tmux 复制模式，此选项也影响其他全屏程序。普通 Shell 历史、鼠标滚轮、Shift 滚动和 Ctrl 字体缩放保持原行为。

MyTerm 内关闭 macOS 长按字母的重音字符菜单，英文输入法下长按 `h/j/k/l` 等字母会连续输入，便于 Vim 导航。此行为仅作用于 MyTerm，不修改系统全局偏好；中文组合输入仍经由输入法处理。重复速度和延迟沿用 macOS 的键盘设置。

首次双击选择空白分隔的文本，再次双击选中文本扩展为完整逻辑行。复制默认合并已记录的自动折行、保留硬换行；可用“复制（保留屏幕换行）”保留视觉排版。远端启用鼠标报告时，可按住 Shift 本地选择。全屏程序若仅按坐标重画、未传递折行关系，复制结果仍可能按屏幕分行。

终端底栏可选择 UTF-8、GB2312、GBK、GB18030、Big5、Shift-JIS、EUC-KR、ISO-8859-1。编码切换只影响后续输入输出，无法表示的字符使用替代字符；不修改 SFTP、ZMODEM 的二进制数据。

### tmux 与屏幕共享

新 PTY 使用 `xterm-256color`，清除继承的 TMUX、TMUX_PANE、LINES、COLUMNS 等环境变量。远端 shell 和 tmux 需要有效的 UTF-8 locale；不要在 shell 配置中无条件覆盖 TERM。默认 `Ctrl+B` 前缀后的一个普通按键使用 ASCII 键盘布局，中文输入法下也可按对应物理按键进入 tmux 复制模式；不改变后续中文输入，也不识别自定义前缀。

布局变化会合并处理并过滤零尺寸，尺寸按 AppKit 逻辑点计算。底栏“锁定尺寸”可在窗口缩放、侧栏切换时保持终端区域大小，较小窗口可滚动查看；取消后恢复自动适配。手动改变字体仍会改变行列数，此选项不控制其他远端 tmux 客户端或会议软件的采集行为。

## 历史与日志

内存回看历史另有全局预算：默认 **256 MiB**，在所有终端标签（包括保留退出画面的标签）间均分，可在 **设置 → 终端行为 → 历史内存预算** 调整为 16–16,384 MiB，或设为 **0** 仅使用行数限制。应用按行宽和字符存储成本估算可保留行数，并同时遵守单会话行数上限；这不是进程总内存硬上限，不含当前屏幕、图片及界面。打开更多标签、加宽窗口或降低预算可能淘汰最旧的回看内容，已淘汰内容无法恢复；已有磁盘日志不受影响，关闭日志也不会关闭内存回看缓存。

**日志默认不保存到磁盘**。在 **设置 → 终端行为** 设置全局默认，SSH 配置或标签右键菜单可选择跟随全局、始终保存或不保存。

回滚/保存行数默认 50,000 行，可调整；单个历史文件默认上限 20 MiB，总容量 500 MiB。默认 gzip 快速压缩，压缩和磁盘操作在后台执行，容量按压缩后文件大小计算。超限保留较新的文本，并清理最久未更新记录。

启用日志后，每 30 秒、关闭标签及退出应用时保存历史快照到 `~/Library/Application Support/MyTerm/History/`。它不是无限日志或录像：清屏删除、超出回滚范围的内容无法补回，全屏程序只附加当前画面。异常退出可能丢失尚未保存的快照。

**文件 → 会话历史…** 可筛选、查找、导出、删除记录，或清理 30 天前及全部记录。删除活动会话的记录后，本次连接不再自动生成该记录。**文件 → 导出当前会话文本…** 保存 UTF-8 文本，去除 ANSI 控制序列和宽字符占位符；手动导出不受自动日志开关影响。

## 密码与密钥

目标 SSH 服务器的密码在认证窗口输入，勾选“登录成功后记住密码”后验证成功才保存；下次自动使用，旧密码被拒绝时提示更新。修改名称、日志、压缩或端口转发不会丢失密码关联。目标服务器的可识别密码提示按会话、主机、用户、端口及跳板路径隔离，自定义提示仅用于本次认证。密钥口令和验证码不自动保存。

详细配置的跳板机密码按地址、端口、用户名、前置跳转路径及网络代理共享，不依赖目标会话。编辑器填写的密码在点击保存时写入本地加密数据库，留空不会清除；认证时记住的密码在登录成功后保存。密码管理显示引用它的各会话；修改共享密码会影响同一路径的后续连接。密码不会写入会话 JSON 或 OpenSSH 配置。同一提示无法区分多个端点或未明确用户名时，仍使用交互认证。

**设置 → SSH 密码** 可命名、查看关联会话、更新、删除或清空已保存密码，更新只改变本地记录。查看密码需显式点击，离开页面或窗口失焦后隐藏。密码不写入终端历史、服务器 JSON、进程参数或环境变量。

凭据使用应用自管 SQLite 和 CryptoKit AES-256-GCM，不读写系统钥匙串。目录为 `~/Library/Application Support/MyTerm/Credentials/`，数据库 `passwords.sqlite`、密钥 `encryption.key`，目录权限 0700、文件权限 0600。为支持无主密码自动登录，密钥保存在本机；同时取得数据库和密钥的进程可以解密。手工备份须同时保存两者。

**设置 → SSH 密钥** 支持导入 OpenSSH / PEM 私钥（包括加密格式）、查看公钥和删除应用内副本；是否能认证仍受系统 OpenSSH、服务端算法和硬件密钥设备限制。导入保留原始字节，同名 `.pub` 一并复制，不删除原文件或去除口令。文件保存在 `~/Library/Application Support/MyTerm/Keys/`，可在 SSH 编辑窗口通过“密钥库”选择，也可直接引用外部私钥。

密钥列表显示应用内显式引用的服务器、保存会话、活动标签和跳板机；删除被引用密钥需额外确认。外部程序或 SSH 配置中的隐式引用不在统计范围内。

## 配置保存、导入与备份

服务器、分组和保存的多标签会话分别存放在 `~/Library/Application Support/MyTerm/` 下的 `servers.json`、`groups.json`、`sessions.json`。分组调整不修改认证或活动连接。损坏的配置保留原文件；分组信息可按提示修复或移除。

- **导出/导入会话配置**：使用版本化 JSON 迁移服务器、分组和已保存的多标签会话；活动标签需先保存。密码、私钥文件和终端历史不包含在内。导入不发起连接，完全相同的记录跳过，冲突或无效文件取消整次导入。文件上限 20 MB。
- **导出 OpenSSH 配置**：在“文件”菜单导出，可用 `ssh -F /path/to/config Host别名` 连接。支持认证、跳板、代理、转发等参数，保留对 SSH 配置的 Include 引用。密钥、SSH 别名及代理助手等依赖需在目标机器另行配置，不是独立完整备份。
- **导出/恢复偏好设置备份**：使用口令加密的 `.mytermbackup`，包含服务器、分组、保存会话、活动标签配置快照、主题、语言、终端偏好、SSH 密码及应用密钥库。终端历史、外部 SSH 配置、外部私钥和已安装字体不打包；Codex 独立代理密码库也不包含。

偏好备份通过口令派生密钥并使用 AES-256-GCM 加密校验；忘记口令无法恢复。恢复先验证，再确认替换配置并关闭连接；写入失败尝试回滚。应用内密钥路径会适配用户目录，恢复后重启以应用全部偏好。

## 测试与源码

完整功能与测试入口对应关系、统一回归命令及验证边界见 [测试与维护](docs/TESTING.md)。


在仓库根目录运行：

```bash
bash scripts/check.sh
bash scripts/check-integration.sh
```

核心检查覆盖 SSH 参数、配置、PTY、进程回收、MCP、传输检测，以及真实 SFTP 服务下的文件/目录传输、中断续传、冲突和符号链接处理。集成检查使用临时本地 sshd、代理与回显服务验证认证、跳转、转发及连接复用，不修改用户 SSH 配置。

窗口与传输检查：

```bash
python3 scripts/window-controls-check.py dist/MyTerm.app
dist/MyTerm.app/Contents/MacOS/MyTerm --smoke-test --transfer-check
MYTERM_TMUX_CHECK=1 bash scripts/check-integration.sh
MYTERM_TRZSZ_CHECK=1 bash scripts/check-integration.sh
```

窗口检查覆盖菜单、标签、布局、中英文设置及 SFTP 交互。传输检查使用 Debug 应用；ZMODEM / tmux 检查需安装对应工具。密码认证测试使用独立虚拟环境及临时凭据库：

```bash
python3 -m venv .test-venv
.test-venv/bin/python -m pip install -r scripts/requirements-password-test.txt
bash scripts/check.sh
.test-venv/bin/python scripts/password-check.py
```

- `Sources/MyTerm`：窗口、表单、终端、传输界面及应用内检查。
- `Sources/MyTermCore`：SSH 配置、持久化、SFTP、续传及 MCP 协议。
- `Sources/MyTermProxy`：HTTP CONNECT / SOCKS5 代理助手。
- `Tests/MyTermCoreTests`、`scripts/`：核心、集成、打包及安装验证。

功能变更和历史发布记录统一维护在 [CHANGELOG.md](CHANGELOG.md)，README 描述使用方式与边界，不维护固定的“最新版本”编号。
