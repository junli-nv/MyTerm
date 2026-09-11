# MyTerm 1.1

Build 104 · Apple Silicon (arm64) · macOS 14 or later

## trzsz 与 tmux 文件传输 / trzsz and tmux transfers

- 内置 trzsz-go 1.2.0 客户端，SSH 会话默认启用，可在编辑会话时关闭。
- 远端安装 trz/tsz 后，执行 `trz` 上传、`tsz 文件名` 下载；支持文件和目录、进度与速度显示，以及 Ctrl+C 后选择停止传输。
- 拖拽协议可选自动、trzsz 或 ZMODEM。自动模式在普通 shell 使用 ZMODEM，在 tmux 等备用屏幕中使用 trzsz；请仅在 shell 提示符下拖拽，不要在编辑器中使用。
- 设置保存后重新打开 SSH 连接生效。保留原有 OpenSSH 密码/密钥认证、代理、多级跳转、端口转发及 SFTP 功能。

Bundles the official trzsz-go 1.2.0 client for SSH transfers, including tmux, file/directory drag uploads, downloads, progress, speed and cancellation. Remote hosts need trz/tsz installed. The per-session switch and drag protocol selection take effect on a new connection. OpenSSH authentication and connection options are preserved.

如果在中间服务器的 tmux 中手工 SSH 到下一台机器，需在中间机安装客户端并使用 `trzsz --relay ssh 目标`。应用配置的 ProxyJump 无需这种手工中继。

## 验证 / Validation

Debug 和 Release 核心检查通过；实际 PTY/tmux 上传、下载、目录拖拽、中文及带引号路径、文件内容一致性、取消与尺寸同步通过。另已验证 11 组 SSH 代理/跳转组合、端口转发、SFTP、密码保存与变更、R/r 重连，以及原有 ZMODEM 的实际窗口传输。

## Install / 安装

Open the DMG (or unzip the ZIP archive) and drag `MyTerm.app` into Applications. Quit any previous copy before replacing it. Existing preferences remain in `~/Library/Application Support/MyTerm` and the app's preferences domain. Export an encrypted preferences backup before upgrading.

打开 DMG（或解压 ZIP）后将 `MyTerm.app` 拖入“应用程序”。替换前退出旧版；已有配置继续使用。建议升级前通过“文件 → 导出偏好设置备份…”备份数据。

## Distribution status / 分发状态

This package is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded copies. It is intended for local/manual distribution; Developer ID signing and Apple notarization are still needed for a conventional public macOS release. No user credentials, private keys or personal configuration are included in this package.

当前包为临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。下载后 macOS 可能阻止打开；用于本地或手动分发。面向公众的常规 macOS 发布仍需完成正式签名与公证。发布包不包含用户密码、私钥或个人配置。

## Dependencies and limits / 依赖与限制

- ZMODEM requires separately installed `lrzsz` on the Mac and remote host; it is not bundled.
- X11 requires a running local XQuartz server and remote X11 support. Actual X11 window rendering has not been tested in the build environment.
- SCP resume uses SFTP; the remote server must support SFTP. SCP speed is sampled from staging-file sizes.
- HTTP/SOCKS5 proxies without authentication are supported.
- Backups include app-managed keys, not external private keys, external SSH configuration or installed fonts. Keep backup passphrases safe.
- OpenSSH exports reference SSH configuration, key paths and the MyTerm proxy helper where applicable.
- This build targets Apple Silicon only. Intel Macs and the macOS 14 minimum have not been independently tested.

SwiftTerm's MIT license is included in `MyTerm.app/Contents/Resources/SwiftTerm-LICENSE.txt`.

trzsz-go 的 MIT 许可和第三方许可随应用附带于 `Contents/Resources/trzsz-LICENSE.txt` 及 `trzsz-THIRD-PARTY-NOTICES.txt`。上游项目：https://github.com/trzsz/trzsz-go 。
