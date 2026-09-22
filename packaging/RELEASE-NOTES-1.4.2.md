> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.4.2)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.4.2).

# MyTerm 1.4.2

Build 110 · Apple Silicon (arm64) · macOS 14 or later

## 设置标签与排版 / Settings tabs and alignment

- 设置使用六个固定显示、等宽且支持两行标题的标签，不再使用会折叠到溢出菜单的自适应 TabView。
- 切换语言保留当前页，标签标题即时更新；直接点击标签即可访问所有设置。
- 主题与字体采用统一的左标签、右控件布局，对齐预设、外观、字体、搜索、自定义字体及字号。
- 增加完整设置窗口回归：反复切换中英文，真实点击全部六个标签，检查尺寸、翻译、选中状态及内容。开发版、正式版、DMG 复制版与安装版均执行该检查。

Replaces adaptive settings tabs with six explicit tabs that stay visible during language changes. Aligns theme/font form labels and controls. Release validation repeatedly changes the language and clicks every tab in the complete settings window.

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
