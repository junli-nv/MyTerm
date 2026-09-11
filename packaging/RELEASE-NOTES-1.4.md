# MyTerm 1.4

Build 108 · Apple Silicon (arm64) · macOS 14 or later

## 配色和透明度 / Colors and opacity

- 主题与字体新增标准/明亮 ANSI 16 色、光标文字、选区文字和 HEX 输入。
- 新增午夜蓝、柔和纸白预设，补齐 Solarized ANSI 调色板。
- 支持 .itermcolors 基础颜色及 ANSI 颜色导入导出；支持 sRGB、Calibrated 和 P3 输入，导出 sRGB。不会改变字体、字号或当前透明度。
- 新增背景不透明度 0–100%，默认 100%。只影响默认终端背景和左右留白，文字、光标、选区以及程序指定的背景颜色保持不透明。
- 颜色即时应用，旧主题自动补全新增字段，完整配置随偏好设置备份保存。
- 发布检查覆盖主题迁移、导入导出、异常输入、持久化、颜色/透明度应用，以及开发版和安装版的窗口交互。

Adds configurable ANSI palettes, cursor/selection text colors, HEX entry, new presets, iTerm color file import/export, and default-background opacity without dimming text. Existing themes migrate with compatible defaults.

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
