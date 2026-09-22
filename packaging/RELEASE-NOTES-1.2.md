> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.2)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.2).

# MyTerm 1.2

Build 105 · Apple Silicon (arm64) · macOS 14 or later

## 窗口与标签页 / Window and tabs

- 移除独立标题栏和分栏内部额外留白，顶部合并为单行标签栏。实测终端顶部占用由 63 点降至 31 点，保留系统窗口控制按钮。
- 新会话的底部状态栏默认隐藏；点击标签栏左侧底栏图标可展开 SFTP、编码和尺寸锁定选项。连接退出或断线时仍显示状态。
- Ctrl+Tab 切换到下一个标签页，Ctrl+Shift+Tab 切换到上一个，支持首尾循环；“窗口”菜单提供对应操作。
- 双击标签栏空白处最大化 / 还原窗口，拖动空白处移动窗口；右键空白处仍可打开新会话菜单。

Combines the title area and tab strip into one compact row, hides the bottom status bar by default, adds Ctrl+Tab / Ctrl+Shift+Tab cycling, and supports double-click zoom/restore and window dragging in unused tab-strip space.

保留 1.1 的 trzsz/tmux 文件传输及现有 SSH、SFTP、SCP、ZMODEM、分组和凭据管理功能。trzsz 的远端仍需安装 trz/tsz。

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
