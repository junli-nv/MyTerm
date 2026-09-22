> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.4.1)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.4.1).

# MyTerm 1.4.1

Build 109 · Apple Silicon (arm64) · macOS 14 or later

## 设置布局修复 / Settings layout

- 主题与字体使用完整可用宽度，移除表单列对复杂配色区域的宽度压缩。
- 预设按钮自动分行；字体与外观标签独立显示，长字体名称和说明文字换行。
- 颜色名称位于色块和 HEX 框上方，基础颜色和 ANSI 颜色按两列对齐；透明度标签独立显示。
- 在实际设置页 736×550 可用区域检查中文和英文布局与纵向滚动，并将检查纳入 Debug、Release 和安装包验证。

Uses the full settings width, wraps preset buttons and explanatory text, and separates labels from color controls to avoid truncation. Validates Chinese and English at the actual tab size in development and installed builds.

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
