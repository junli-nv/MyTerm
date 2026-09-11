# MyTerm 1.2.1

Build 106 · Apple Silicon (arm64) · macOS 14 or later

## 面板与窗口交互修复 / Panel and window interaction fixes

- 修复紧凑标签栏处于原生分栏宿主安全区域时，图标可见但点击无法传给控件的问题。标签栏移至分栏外层，保留单行紧凑高度。
- 侧栏与底栏按钮采用明确的完整点击区域；SSH 会话增加独立 SFTP 面板按钮，不再依赖先展开底栏。
- 空白处实际发生鼠标移动后才进入窗口拖动，避免第一次按下立即进入拖动处理而干扰双击最大化/还原。
- 发布脚本强制在 Debug 和最终 Release 应用中运行相同的窗口交互检查，包含实际鼠标事件、面板布局变化、双击最大化/还原和切换标签后的状态。任一失败都会阻止生成发布归档。

Moves interactive tabs outside the native split-view safe-area host, fixes panel button hit regions, adds a direct SFTP panel toggle, and starts window dragging only after mouse movement. Packaging requires the same real-window interaction checks to pass in Debug and Release.

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
