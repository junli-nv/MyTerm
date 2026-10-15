# MyTerm 3.2.2

## 简体中文

在分屏标签的右上角点击“广播命令”（天线图标），或从区域菜单打开。默认不选目标；勾选当前标签中的 SSH / 本地 Bash 分屏，所选区域显示广播标记。输入单行命令（最多 4096 字节，不含换行或控制字符），确认所有目标均处于空白 Shell 提示符，再点击“发送并执行”。结果分别显示在各自终端；“已发送”仅表示输入已提交，不代表远端命令成功。每次发送后清空输入并重新确认，不同步日常键盘操作。

Codex 标签、尚未认证的 SSH、已断开的会话和正在进行 ZMODEM 传输的终端不可选。发送时重新核对全部目标，任何目标已重连或不可用时整批不发送；不会在重连后补发。广播不是远程事务，提交后若发生网络中断，部分目标仍可能已收到命令。MyTerm 无法可靠识别远端是否正在运行 Vim、less、等待密码或其他交互程序，请先返回空白 Shell 提示符；已有半行输入也会与命令拼接。结束广播、切换标签或调整分屏结构会清除选择，广播配置不保存。

### 检查更新

通过菜单 **MyTerm → 检查更新…** 手动查询 GitHub 最新正式版。窗口显示当前版本、新版本和发布说明；点击“下载并安装”并确认后，应用会下载对应架构的 ZIP，验证 SHA-256、应用标识、版本、架构和代码签名，再结束当前终端会话、替换应用并重新启动。请先保存远端和本地正在进行的工作；设置与保存的会话配置会保留，运行中的进程不会恢复。安装失败时保留或恢复旧应用，诊断日志位于 `~/Library/Logs/MyTerm/Update.log`。

仅在手动检查时访问 GitHub，不自动轮询，不借用 SSH 或 Codex 的代理配置；使用 macOS 网络设置。GitHub API 限流时会尝试公开发布页，并提供发布说明链接；查询仍失败或安装包不兼容时会明确提示。当前应用须位于可写位置并命名为 `MyTerm.app`，建议使用 `/Applications/MyTerm.app`；不能从只读 DMG 中原地更新。只提供高于当前版本的正式版，不降级、不安装预发布版。下载与校验阶段可取消或关闭更新窗口。

## English

Click Broadcast Command (the antenna icon) at the top right of a split tab, or open it from a pane menu. No targets are selected by default. Select SSH or local Bash panes in the current tab; selected panes show a broadcast marker. Enter a single-line command (up to 4096 bytes, without newlines or control characters), confirm every target is at an empty shell prompt, then click Send and Execute. Each terminal displays its own results. “Sent” means input was submitted, not that the remote command succeeded. After each send, the command is cleared and readiness must be confirmed again. Ordinary keystrokes are not broadcast.

Codex tabs, unauthenticated SSH connections, disconnected sessions and terminals transferring via ZMODEM are unavailable. All targets are revalidated before sending; if any reconnected or became unavailable, nothing is sent. Input is never replayed after reconnection. Broadcasting is not a remote transaction: a network failure after submission may leave some targets having received the command. MyTerm cannot reliably detect Vim, less, password prompts or other interactive programs on the remote host. Return every target to an empty shell prompt first; partially typed input would be combined with the command. Ending broadcast, switching tabs or changing split structure clears the selection. Broadcast configuration is not saved.

### Check for updates

Use **MyTerm → Check for Updates…** to query the latest stable GitHub release manually. The window shows your version, the new version and release notes. After you choose Download and Install and confirm, MyTerm downloads the ZIP for your architecture, verifies SHA-256, application identity, version, architecture and code signature, then ends current terminal sessions, replaces the app and restarts it. Save ongoing remote and local work first. Settings and saved session configurations are retained; running processes are not restored. Installation failures retain or restore the previous app. Diagnostics are written to `~/Library/Logs/MyTerm/Update.log`.

Checks are manual, with no automatic polling. They use macOS networking settings independently of SSH and Codex proxy configurations. When the GitHub API is rate-limited, MyTerm tries the public release page and provides a link to release notes. Failed lookups and incompatible installers are reported explicitly. The app must be named `MyTerm.app` in a writable location; `/Applications/MyTerm.app` is recommended. An app on a read-only DMG cannot update in place. Only newer stable releases are offered, never downgrades or prereleases. Cancel or close the update window to stop downloading or preparation.
