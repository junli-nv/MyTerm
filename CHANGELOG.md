# MyTerm 历史更新日志

保留仓库记录的各版本说明，按版本从新到旧排列。旧 Release 安装包清理后，本日志和各版本原始说明仍保留。历史说明中的安装路径、依赖及限制以对应版本为准。


<a id="version-1.6.9"></a>

## MyTerm 1.6.9（Build 134）

- 修复 Codex 执行控制每半秒无条件刷新整个界面的问题：只有命令状态或输出变化时才更新，降低历史记录积累后的布局开销。
- 没有有效授权且没有运行命令时停止执行轮询，重新授权后恢复；清理已关闭 SSH 会话的额度配置。
- 执行历史采用惰性布局；轮询只读取轻量状态，不复制或解码命令输出。
- 增加连续 1000 次无变化轮询不刷新界面、空闲停表和续期恢复检查，保留 SSH 审批、输出完整性及授权撤销验证。

Apple Silicon 版本，临时签名，未进行 Apple 公证。

<a id="version-1.6.8"></a>

## MyTerm 1.6.8（Build 133）

- 重排 SSH 接入入口：登录独立于会话权限，启动时统一选择目标与权限并开启接入；外部 MCP 注册单独列为可选。
- 启动 Codex 标签时可手工设置执行授权时长（1–1440 分钟）和命令额度（1–10000 条），默认 60 分钟、300 条。
- 当前 Codex 标签显示到期状态与剩余命令额度，可点击继续授权，沿用当前会话配置重新计时并重置额度，无需新建标签。
- 默认只读、逐条命令批准和输出完整性检查保持生效。重新授权会拒绝旧待确认命令，需重新提交审批。

Apple Silicon 版本，临时签名，未进行 Apple 公证。

<a id="version-1.6.7"></a>

## MyTerm 1.6.7（Build 132）

- 修复只读状态无法提交排查计划的问题；可在当前 Codex 标签重新授权，无需重新创建标签。
- 修复旧 Codex 标签退出撤销其他标签新授权的问题；每条 SSH 命令仍需明确批准。
- SSH 执行及命令审批按钮采用单行布局；计划默认展开，支持收起和再次展开，保留取消入口。
- SSH/SFTP 连接显式设置 StrictHostKeyChecking=no。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.6"></a>

## MyTerm 1.6.6（Build 131）

- 排查计划直接展示，不再要求确认计划。可在同一 Codex 标签点击“取消计划并停止执行”，拒绝待执行命令并撤销执行授权。
- 每条 SSH 命令均需通过按钮明确确认，包括诊断命令。标签标题和内容区显示待确认提示、目标、完整命令及理由；不使用 Y/y 快捷确认。
- 移除 Codex 接入页的重复 SSH 选择，仅在“启动 Codex 标签”时从会话列表选择目标。
- 创建 Codex 标签后自动关闭接入和选择窗口；需要另开标签时可重新打开接入入口。
- 保留默认只读、输出完整性、取消、超时及断线撤权检查。增加计划取消、诊断命令确认和启动窗口关闭检查。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.5"></a>

## MyTerm 1.6.5（Build 130）

- Codex SSH 执行计划和命令确认移至对应 Codex 标签页，授权及提交计划时不再自动弹出独立执行窗口。
- 计划、命令理由和结果由 Codex 在终端中展示；同标签下方提供可滚动的内容、确认和拒绝按钮。
- 执行记录可在标签内展开查看，停止按钮仅撤销当前关联 SSH 会话的执行授权。外部 Codex 可继续从接入设置手动打开执行控制窗口。
- 保持默认只读、显式执行授权、默认开启且可关闭的计划确认，以及输出完整性、超时和撤权检查。
- 增加无自动弹窗和中英文同标签确认界面检查，执行 Debug、Release、实际 DMG 副本及安装版完整验证。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.4"></a>

## MyTerm 1.6.4（Build 129）

- 新增按 SSH 标签明确授权的 Codex 命令执行，默认仍为只读。复用已认证 SSH 连接上的独立非交互通道，与 Codex 代理隔离，不共享终端目录、环境变量或 tmux 状态。
- 执行前确认计划默认开启，可在启动选项中关闭。授权后固定诊断清单内的命令自动执行，其他命令显示完整内容和理由，须逐条确认。
- 命令输出按任务 ID 和偏移分页读取；未读完上一条输出或跳过分页时不允许继续执行。输出超限、取消或超时明确标记不完整并停止自动推进。
- 每次授权最多 10 分钟、30 条命令；单条最多 60 秒和 1 MB 输出。支持停止和撤权，断线、重连或关闭拥有执行权限的 Codex 标签后撤权。停止通道不能保证终止远端已脱离会话的后台进程。
- 新增中英文可滚动执行控制窗口，保留命令、状态及输出预览；记录仅在内存中保留。
- 增加真实本地 SSH 连接复用执行、默认权限、计划确认开关、输出完整性和撤权检查，并纳入发布验证。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.3"></a>

## MyTerm 1.6.3（Build 128）

- 修复 Codex MCP 启动路径错误：Foundation 的 JSON 编码将路径斜杠转义为 TOML 不接受的形式，导致 required MCP 初始化报 No such file or directory，Codex 随后以 exit=1 退出。
- 保留路径中的普通斜杠，同时正确处理空格、引号和 Unicode。
- 外部 MCP 注册状态、实际路径和最近检查时间直接可见，配置后自动回读验证。
- Codex 退出时针对 MCP 路径、服务初始化、登录凭据、网络和配置错误给出具体处理提示，保留原始报错。
- 安装包验证新增真实 Codex CLI 解析生产启动参数，并使用解析结果启动 MCP、验证初始化和五个只读工具。Debug、Release、DMG 副本和安装版均执行此检查，无需调用模型。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.2"></a>

## MyTerm 1.6.2（Build 127）

- 启动 Codex 分析前检查已有登录；需要认证时，登录成功后自动继续原先选定的 SSH 分析任务。
- 普通登录按钮复用已有凭据，增加检查登录状态与主动重新登录入口。状态检查、登录和分析统一使用 Codex 文件凭据存储，不修改全局配置。
- Codex 退出后保留标签、输出和退出码，不再沿用本地 Bash 的自动关闭逻辑。分析界面使用普通屏幕保留诊断信息。
- 增加真实 PTY 登录到分析的衔接检查，以及默认不监控、退出诊断和中英文界面回归检查。

本地登录状态不代表服务端凭据一定有效，撤销或切换账号时可主动重新登录。SSH 与普通本地 shell 的退出行为保持不变。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6.1"></a>

## MyTerm 1.6.1（Build 126）

- 新增 Codex 只读 MCP 接入：按 SSH 标签授权读取输出，无需保存或下载日志。共享每次启动默认关闭。
- Codex 支持独立的 HTTP／SOCKS5 代理及认证，与 SSH 的配置、密码存储和进程环境隔离。
- 启动 Codex 前选择 SSH 标签，自动分析所选历史。持续监控默认关闭，每次需主动勾选，可停止监控或撤销共享。
- 历史范围可设置为 500–10000 行、64 KB–1 MB，默认 2000 行／256 KB。冻结快照并分页读取，避免只取末尾 8 KB 或刷屏造成分页漏行；达到总上限明确提示截断。
- MyTerm 启动的 Codex 对五个只读 MCP 工具配置免重复审批，并要求直接调用 MCP；不修改全局本地命令审批。
- 完善中英文可滚动的会话选择与接入设置界面，保留原有六个设置标签。

需要另行安装 Codex CLI。持续监控会使用模型额度，任务停止后需重新启动，不是无人值守告警服务。无法恢复已从终端缓冲区移出的历史。外部 IDE／浏览器代理需单独配置；独立 Codex 代理密码库暂不包含在偏好备份中。

验证包括 Debug、Release、实际 DMG 副本及安装后完整界面检查、核心检查与应用内容一致性校验。完整历史说明见随 Release 提供的 CHANGELOG.md。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.6"></a>

## MyTerm 1.6（Build 125）

- 新增 Codex 只读 MCP 接入，可读取授权 SSH 标签的近期输出、当前屏幕和选中文本，无需保存或下载日志。共享默认关闭，每次启动需重新授权。
- 新增独立的 Codex HTTP／SOCKS5 代理设置，支持代理认证。配置、密码存储及进程环境与 SSH 代理隔离；修改设置仅影响之后启动的 Codex 进程。
- 支持启动本地 Codex 标签、设备码登录，以及配置外部 Codex 的 MyTerm MCP。外部 IDE 和浏览器的代理需要单独配置。
- 提供有大小限制的增量读取、授权撤销和中英文可滚动设置窗口；保留原有六个设置标签。

需要另行安装 Codex CLI。Codex 代理密码保存在独立的应用本地加密存储中，第一版偏好备份不包含此密码库。详见仓库 docs/CODEX-INTEGRATION.md。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.5.2"></a>

## MyTerm 1.5.2（Build 124）

- 修复 SSH 中输入星号后需等待下一个字符才显示的问题：立即显示可打印的星号，同时保留副本识别 ZMODEM 握手，避免重复输出。
- 保持跨数据包、逐字节到达的 ZMODEM 握手识别，覆盖普通文本和无效握手的回归检查。
- Debug 和 Release 均支持真实 ZMODEM 上传、下载及拖拽上传自检，校验文件内容一致。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.5.1"></a>

## MyTerm 1.5.1（Build 123）

- SSH 密钥管理显示关联服务器、保存会话、已打开标签和各级跳板机，支持展开用户目录和符号链接路径匹配。
- 删除被引用的密钥时列出受影响会话，并要求额外确认；取消任意一次确认都会保留密钥。
- 删除前重新检查关联信息，确认期间出现新引用时停止删除，避免误删。
- 完善中英文关联提示和长会话名称的换行、滚动显示。

关联统计覆盖应用内显式设置的密钥路径，不包含外部程序或 SSH 配置文件的隐式引用。删除应用内密钥副本不会修改会话配置或原始导入文件。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.5"></a>

## MyTerm 1.5（Build 122）

- SSH 密码管理支持自定义名称，更新密码后保留名称，偏好设置备份包含密码名称。
- 显示密码关联的服务器、已保存会话及已打开标签；无法匹配的旧记录明确标注。
- 支持按需查看、隐藏当前保存的密码，默认隐藏，离开页面或窗口失去焦点时自动隐藏。
- 完善密码管理页面的中英文文案和可滚动布局。

继续使用应用本地加密密码库，无需系统钥匙串。仅修改本地保存的密码不会修改服务器密码。

Apple Silicon 版本，临时签名，未进行 Apple 公证。


<a id="version-1.4.13"></a>

## MyTerm 1.4.13

- 修正持续输出时选区被每批新数据清除的问题。
- 选择普通终端历史时暂停画面自动跟随，输出继续写入回滚记录；取消选择并滚回底部后恢复跟随。
- 保留全屏程序中本地选择的文本，继续遵守远端鼠标报告和 Shift 本地选择规则。
- 回归验证输出与鼠标拖动交错、复制、持续接收数据及恢复跟随。


<a id="version-1.4.12"></a>

## MyTerm 1.4.12

- SSH 断开后保留普通历史及全屏程序最后画面，恢复显示模式并显示 R/r 重连提示。
- 修正焦点停留在控件上时 R/r 不能重连；隐藏会话及输入框不会截获按键。
- 固定终端视图结构，避免 SFTP 对象在断线时移除导致终端重建。
- 包含两级双击文本/整行选择改进。


<a id="version-1.4.11"></a>

## MyTerm 1.4.11

- 首次双击选择以空白分隔的文本，包括路径、URL、标点和跨自动折行的内容。
- 在选中文本上再次双击，扩展为完整逻辑行；支持快速连续四击及两次独立双击。
- 点击其他文本重新开始选择；保留远端鼠标报告及 Shift 本地选择。
- 回归验证中文、字体缩放、真实换行边界和两级鼠标选择。


<a id="version-1.4.10"></a>

## MyTerm 1.4.10

- 默认复制合并自动折行，保留真实换行；修正重绘后残留的折行标记，避免独立短行被误拼接。
- 字体缩放后按逻辑行复制；Shift+右键菜单可选择「复制（保留屏幕换行）」。
- 双击选中完整逻辑行，向前、向后包含自动折行的内容，保留真实换行边界。
- 行选择覆盖最后一列，拖动扩选沿逻辑行边界扩展。
- 验证普通及全屏终端、中文、字体缩放，以及远端鼠标报告和 Shift 本地选择。
- 仍依赖远端传递的折行关系；未携带关系的逐行重绘无法可靠还原原文边界。

验证：21 项核心检查，Debug、Release、实际 DMG 副本和安装版的复制及窗口回归检查；安装版与 dist/MyTerm.app 文件一致。

安装包面向 Apple Silicon。当前使用临时签名，尚未进行 Developer ID 签名与 Apple 公证。


<a id="version-1.4.9"></a>

## MyTerm 1.4.9

- 修正 1.4.8 在全屏终端复制时强制插入屏幕换行的行为，默认恢复自动折行合并。
- 显式换行和行尾擦除会修正旧折行关系，避免短行重绘后被误合并。
- 增加字体缩放前后、中英文长行及恰好占满一行后换行的回归检查。
- 需要保留视觉排版时，可使用 Shift+右键 → 复制（保留屏幕换行）。

已知限制：tmux/less 使用光标定位逐行重画且未传递折行关系时，仍可能按屏幕分行复制；本次修复不会猜测合并这些边界，以免破坏真实换行。


<a id="version-1.4.8"></a>

## MyTerm 1.4.8

- 全屏程序（含 tmux/less）复制默认保留屏幕行，避免重绘造成的折行标记将多行合并。
- 选中自动复制、⌘C 和右键复制使用同一规则；普通 shell 的自动折行仍按原规则合并。
- 新增「复制（合并自动折行）」菜单，可通过 Shift+右键访问，适用于需要拼接全屏程序长行的场景。
- 加入真实 tmux/less 翻页、回翻、搜索和缩放输出回放，以及空行、中文和反向选区回归检查。


<a id="version-1.4.7"></a>

## MyTerm 1.4.7

- 修复端口转发配置文字截断，监听与目标端口标签改为输入框上方显示。
- SSH 配置改为可调整大小的独立窗口，支持最大化/还原与系统全屏。
- 长配置区域显示固定滚动栏，底部取消、保存及保存并连接按钮保持可见。
- 加入多级跳板机、代理、三种端口转发同时展开时的中英文、小/大窗口及最大化回归检查。


<a id="version-1.4.6"></a>

## MyTerm 1.4.6

- 日志全局开关作为默认值，每个会话支持跟随全局、始终保存、不保存三个选项。
- SSH 编辑窗口可保存会话日志选项；标签右键菜单可即时控制当前 SSH 或本地会话。
- 复制、保存、恢复及 MyTerm 配置导入导出保留覆盖选项；旧配置默认跟随全局。
- 保留后台 gzip 快速压缩及全局行数、文件大小和容量限制。


<a id="version-1.4.5"></a>

## MyTerm 1.4.5

- 默认关闭自动会话日志，需在设置 → 终端行为明确开启；保留已有历史及手动导出。
- 支持配置单会话回滚/保存行数、单历史文件大小和历史总容量。
- 超出行数或文件上限时保留最新文本；总容量超限清理最久未更新记录。
- 历史窗口支持清理 30 天前记录、清空全部历史；删除前确认。
- 新设置支持中英文及偏好设置备份。
- 包含 1.4.4 的 SSH 转义修复，使 ~. 可以传递给远端 ipmitool。

- 默认使用后台 gzip 快速压缩，按压缩后的实际字节计量；兼容旧 JSON 历史，查看和导出自动解压。


<a id="version-1.4.4"></a>

## MyTerm 1.4.4

Build 112 · Apple Silicon (arm64) · macOS 14 or later

### 远端控制台转义键 / Remote console escape keys

- MyTerm 启动的交互式 SSH 增加 `-e none`，禁用外层 OpenSSH 的本地转义键处理。
- 行首 `~.` 等按键原样传给远端，避免退出 ipmitool console 时意外断开外层 SSH。
- 本地 shell、SFTP 和认证配置保持原有行为。SSH 可通过远端 `exit` 或关闭标签页退出。
- 使用真实本机 SSH 服务与 PTY，验证直接 SSH 和 trzsz 包装两种路径均收到原始 `~.\r`，且外层连接继续存活。

Disables local escape processing in the outer interactive SSH client, so remote console escape sequences such as `~.` are delivered unchanged. Verified with real SSH/PTys both directly and through trzsz.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.4.3"></a>

## MyTerm 1.4.3

Build 111 · Apple Silicon (arm64) · macOS 14 or later

### SFTP 开关位置 / SFTP toggle placement

- SFTP 面板开关移到标签栏右侧、加号旁边，仅 SSH 会话显示。
- 本地会话保留相同的布局空间，避免切换本地与 SSH 标签时标签栏位置和宽度变化。
- 窗口回归检查验证右侧按钮位置、本地会话不显示 SFTP 开关，以及切换前后标签栏几何尺寸稳定。

Moves the SFTP toggle beside the right-hand plus button and reserves its space for local shells, keeping the tab strip stable across session switches.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.4.2"></a>

## MyTerm 1.4.2

Build 110 · Apple Silicon (arm64) · macOS 14 or later

### 设置标签与排版 / Settings tabs and alignment

- 设置使用六个固定显示、等宽且支持两行标题的标签，不再使用会折叠到溢出菜单的自适应 TabView。
- 切换语言保留当前页，标签标题即时更新；直接点击标签即可访问所有设置。
- 主题与字体采用统一的左标签、右控件布局，对齐预设、外观、字体、搜索、自定义字体及字号。
- 增加完整设置窗口回归：反复切换中英文，真实点击全部六个标签，检查尺寸、翻译、选中状态及内容。开发版、正式版、DMG 复制版与安装版均执行该检查。

Replaces adaptive settings tabs with six explicit tabs that stay visible during language changes. Aligns theme/font form labels and controls. Release validation repeatedly changes the language and clicks every tab in the complete settings window.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.4.1"></a>

## MyTerm 1.4.1

Build 109 · Apple Silicon (arm64) · macOS 14 or later

### 设置布局修复 / Settings layout

- 主题与字体使用完整可用宽度，移除表单列对复杂配色区域的宽度压缩。
- 预设按钮自动分行；字体与外观标签独立显示，长字体名称和说明文字换行。
- 颜色名称位于色块和 HEX 框上方，基础颜色和 ANSI 颜色按两列对齐；透明度标签独立显示。
- 在实际设置页 736×550 可用区域检查中文和英文布局与纵向滚动，并将检查纳入 Debug、Release 和安装包验证。

Uses the full settings width, wraps preset buttons and explanatory text, and separates labels from color controls to avoid truncation. Validates Chinese and English at the actual tab size in development and installed builds.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.4"></a>

## MyTerm 1.4

Build 108 · Apple Silicon (arm64) · macOS 14 or later

### 配色和透明度 / Colors and opacity

- 主题与字体新增标准/明亮 ANSI 16 色、光标文字、选区文字和 HEX 输入。
- 新增午夜蓝、柔和纸白预设，补齐 Solarized ANSI 调色板。
- 支持 .itermcolors 基础颜色及 ANSI 颜色导入导出；支持 sRGB、Calibrated 和 P3 输入，导出 sRGB。不会改变字体、字号或当前透明度。
- 新增背景不透明度 0–100%，默认 100%。只影响默认终端背景和左右留白，文字、光标、选区以及程序指定的背景颜色保持不透明。
- 颜色即时应用，旧主题自动补全新增字段，完整配置随偏好设置备份保存。
- 发布检查覆盖主题迁移、导入导出、异常输入、持久化、颜色/透明度应用，以及开发版和安装版的窗口交互。

Adds configurable ANSI palettes, cursor/selection text colors, HEX entry, new presets, iTerm color file import/export, and default-background opacity without dimming text. Existing themes migrate with compatible defaults.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.3"></a>

## MyTerm 1.3

Build 107 · Apple Silicon (arm64) · macOS 14 or later

### Changes / 更新

- 终端左右各增加 8 点留白，背景跟随主题，终端列数按可用宽度计算。
- 新增输出着色设置：负面关键词红色、正面关键词绿色、警告黄色；支持自定义关键词、颜色、优先级、完整词和大小写匹配。
- 着色立即生效，默认保留已有 ANSI 颜色。本地终端和 tmux/vim 全屏程序可单独启用；复制、历史导出和传输内容保持原样。
- 着色规则随加密偏好设置备份导入导出。
- 发布流程检查 Debug、Release 和 DMG 复制出的应用，核对安装包与构建产物的文件内容和权限一致。

Adds theme-aware horizontal terminal padding and configurable display-only keyword colors. Packaging validates the same UI behavior in Debug, Release and the application copied from the DMG, and compares all bundle files and permissions.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.2.1"></a>

## MyTerm 1.2.1

Build 106 · Apple Silicon (arm64) · macOS 14 or later

### 面板与窗口交互修复 / Panel and window interaction fixes

- 修复紧凑标签栏处于原生分栏宿主安全区域时，图标可见但点击无法传给控件的问题。标签栏移至分栏外层，保留单行紧凑高度。
- 侧栏与底栏按钮采用明确的完整点击区域；SSH 会话增加独立 SFTP 面板按钮，不再依赖先展开底栏。
- 空白处实际发生鼠标移动后才进入窗口拖动，避免第一次按下立即进入拖动处理而干扰双击最大化/还原。
- 发布脚本强制在 Debug 和最终 Release 应用中运行相同的窗口交互检查，包含实际鼠标事件、面板布局变化、双击最大化/还原和切换标签后的状态。任一失败都会阻止生成发布归档。

Moves interactive tabs outside the native split-view safe-area host, fixes panel button hit regions, adds a direct SFTP panel toggle, and starts window dragging only after mouse movement. Packaging requires the same real-window interaction checks to pass in Debug and Release.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.2"></a>

## MyTerm 1.2

Build 105 · Apple Silicon (arm64) · macOS 14 or later

### 窗口与标签页 / Window and tabs

- 移除独立标题栏和分栏内部额外留白，顶部合并为单行标签栏。实测终端顶部占用由 63 点降至 31 点，保留系统窗口控制按钮。
- 新会话的底部状态栏默认隐藏；点击标签栏左侧底栏图标可展开 SFTP、编码和尺寸锁定选项。连接退出或断线时仍显示状态。
- Ctrl+Tab 切换到下一个标签页，Ctrl+Shift+Tab 切换到上一个，支持首尾循环；“窗口”菜单提供对应操作。
- 双击标签栏空白处最大化 / 还原窗口，拖动空白处移动窗口；右键空白处仍可打开新会话菜单。

Combines the title area and tab strip into one compact row, hides the bottom status bar by default, adds Ctrl+Tab / Ctrl+Shift+Tab cycling, and supports double-click zoom/restore and window dragging in unused tab-strip space.

保留 1.1 的 trzsz/tmux 文件传输及现有 SSH、SFTP、SCP、ZMODEM、分组和凭据管理功能。trzsz 的远端仍需安装 trz/tsz。

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.1"></a>

## MyTerm 1.1

Build 104 · Apple Silicon (arm64) · macOS 14 or later

### trzsz 与 tmux 文件传输 / trzsz and tmux transfers

- 内置 trzsz-go 1.2.0 客户端，SSH 会话默认启用，可在编辑会话时关闭。
- 远端安装 trz/tsz 后，执行 `trz` 上传、`tsz 文件名` 下载；支持文件和目录、进度与速度显示，以及 Ctrl+C 后选择停止传输。
- 拖拽协议可选自动、trzsz 或 ZMODEM。自动模式在普通 shell 使用 ZMODEM，在 tmux 等备用屏幕中使用 trzsz；请仅在 shell 提示符下拖拽，不要在编辑器中使用。
- 设置保存后重新打开 SSH 连接生效。保留原有 OpenSSH 密码/密钥认证、代理、多级跳转、端口转发及 SFTP 功能。

Bundles the official trzsz-go 1.2.0 client for SSH transfers, including tmux, file/directory drag uploads, downloads, progress, speed and cancellation. Remote hosts need trz/tsz installed. The per-session switch and drag protocol selection take effect on a new connection. OpenSSH authentication and connection options are preserved.

如果在中间服务器的 tmux 中手工 SSH 到下一台机器，需在中间机安装客户端并使用 `trzsz --relay ssh 目标`。应用配置的 ProxyJump 无需这种手工中继。

### 验证 / Validation

Debug 和 Release 核心检查通过；实际 PTY/tmux 上传、下载、目录拖拽、中文及带引号路径、文件内容一致性、取消与尺寸同步通过。另已验证 11 组 SSH 代理/跳转组合、端口转发、SFTP、密码保存与变更、R/r 重连，以及原有 ZMODEM 的实际窗口传输。

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。


<a id="version-1.0"></a>

## MyTerm 1.0

Build 103 · Apple Silicon (arm64) · macOS 14 or later

MyTerm is a native macOS terminal and SSH workspace.

### Group validation fix / 分组校验修复

Fixed a Release-only group validation failure caused by a bound Foundation character-set method reference. Ordinary group names now pass the same validation in Debug and Release builds. Release checks are mandatory before packaging.

修复仅在 Release 安装版出现的正常分组名被误判为控制字符的问题。分组名称输入会清理不可见控制字符并提交输入法组合文本。实际损坏的分组文件显示“修复分组”和“移除分组”入口；两种操作均保留备份，服务器配置不会被删除。有效的原有分组直接使用。

### Group startup fix / 分组启动修复

Missing or invalid group data no longer blocks startup or causes repeated alerts. Valid records are recovered where possible; unavailable groups fall back to Ungrouped. Invalid originals are retained and backed up before the next group edit. Explicit configuration imports still validate their contents.

分组为可选数据：正常分组照常加载，缺失或异常时不再重复弹窗。尽量恢复有效记录，其余会话仍可从“未分组”使用。异常原文件保留，并在下次修改分组前备份。

### Updated 1.0 package / 本次 1.0 更新

- New terminal-style application icon, including the About window.
- Improved group-name editing and drag-and-drop movement into, between and out of session groups.
- Optional SSH connection debugging (`-vvv`), off by default.
- Up to 10 ordered jump hosts, with separate address, port, user and password/key authentication settings for each hop. Passwords are requested during connection and may be saved in the encrypted local database after successful login.
- Fixed clipped Chinese custom-font hints and font refresh/apply buttons.
- Updated OpenSSH export for multi-hop configurations and managed jump-key paths during backup restore.

新版图标与“关于”图标、分组输入及拖拽修复、默认关闭的 SSH 调试、多级跳板机独立认证设置，以及中英文字体设置布局修复。

### Highlights / 主要功能

- Local Bash and SSH tabs, session groups, duplication, editing, saved sessions and configuration import/export.
- Password and key authentication, app-managed encrypted password storage, and OpenSSH/PEM key management.
- SSH jump hosts, HTTP/SOCKS5 proxies, compression, keepalive, port forwarding and optional X11 forwarding (off by default).
- SFTP and SCP uploads/downloads, interrupted-transfer resume via SFTP, and real-time/average transfer speeds.
- ZMODEM uploads/downloads and drag-and-drop uploads, with speed display.
- UTF-8, GB2312, GBK, GB18030 and other terminal encodings.
- Themes, custom installed fonts, Ctrl + trackpad font zoom, terminal history/export and locked dimensions for screen sharing.
- Instant Chinese/English interface switching and passphrase-encrypted preferences backups.

### Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

### Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

### Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.
