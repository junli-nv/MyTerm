> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.0)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.0).

# MyTerm 1.0

Build 103 · Apple Silicon (arm64) · macOS 14 or later

MyTerm is a native macOS terminal and SSH workspace.

## Group validation fix / 分组校验修复

Fixed a Release-only group validation failure caused by a bound Foundation character-set method reference. Ordinary group names now pass the same validation in Debug and Release builds. Release checks are mandatory before packaging.

修复仅在 Release 安装版出现的正常分组名被误判为控制字符的问题。分组名称输入会清理不可见控制字符并提交输入法组合文本。实际损坏的分组文件显示“修复分组”和“移除分组”入口；两种操作均保留备份，服务器配置不会被删除。有效的原有分组直接使用。

## Group startup fix / 分组启动修复

Missing or invalid group data no longer blocks startup or causes repeated alerts. Valid records are recovered where possible; unavailable groups fall back to Ungrouped. Invalid originals are retained and backed up before the next group edit. Explicit configuration imports still validate their contents.

分组为可选数据：正常分组照常加载，缺失或异常时不再重复弹窗。尽量恢复有效记录，其余会话仍可从“未分组”使用。异常原文件保留，并在下次修改分组前备份。

## Updated 1.0 package / 本次 1.0 更新

- New terminal-style application icon, including the About window.
- Improved group-name editing and drag-and-drop movement into, between and out of session groups.
- Optional SSH connection debugging (`-vvv`), off by default.
- Up to 10 ordered jump hosts, with separate address, port, user and password/key authentication settings for each hop. Passwords are requested during connection and may be saved in the encrypted local database after successful login.
- Fixed clipped Chinese custom-font hints and font refresh/apply buttons.
- Updated OpenSSH export for multi-hop configurations and managed jump-key paths during backup restore.

新版图标与“关于”图标、分组输入及拖拽修复、默认关闭的 SSH 调试、多级跳板机独立认证设置，以及中英文字体设置布局修复。

## Highlights / 主要功能

- Local Bash and SSH tabs, session groups, duplication, editing, saved sessions and configuration import/export.
- Password and key authentication, app-managed encrypted password storage, and OpenSSH/PEM key management.
- SSH jump hosts, HTTP/SOCKS5 proxies, compression, keepalive, port forwarding and optional X11 forwarding (off by default).
- SFTP and SCP uploads/downloads, interrupted-transfer resume via SFTP, and real-time/average transfer speeds.
- ZMODEM uploads/downloads and drag-and-drop uploads, with speed display.
- UTF-8, GB2312, GBK, GB18030 and other terminal encodings.
- Themes, custom installed fonts, Ctrl + trackpad font zoom, terminal history/export and locked dimensions for screen sharing.
- Instant Chinese/English interface switching and passphrase-encrypted preferences backups.

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
