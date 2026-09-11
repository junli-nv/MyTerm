# MyTerm 1.3

Build 107 · Apple Silicon (arm64) · macOS 14 or later

## Changes / 更新

- 终端左右各增加 8 点留白，背景跟随主题，终端列数按可用宽度计算。
- 新增输出着色设置：负面关键词红色、正面关键词绿色、警告黄色；支持自定义关键词、颜色、优先级、完整词和大小写匹配。
- 着色立即生效，默认保留已有 ANSI 颜色。本地终端和 tmux/vim 全屏程序可单独启用；复制、历史导出和传输内容保持原样。
- 着色规则随加密偏好设置备份导入导出。
- 发布流程检查 Debug、Release 和 DMG 复制出的应用，核对安装包与构建产物的文件内容和权限一致。

Adds theme-aware horizontal terminal padding and configurable display-only keyword colors. Packaging validates the same UI behavior in Debug, Release and the application copied from the DMG, and compares all bundle files and permissions.

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
