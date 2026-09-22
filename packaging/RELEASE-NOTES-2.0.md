# MyTerm 2.0

Build 143 · Apple Silicon (arm64) · macOS 14 or later

## 中文

- 汇总现有 SSH、本地终端、树形分组、标签拖动、SFTP 递归与批量传输、trzsz/ZMODEM、主题、凭据、历史及 Codex 接入功能，完成一次跨模块回归审查。
- 修复 Codex 命令输出包含连续非法 UTF-8 字节时分页游标不前进、后续命令被输出完整性检查阻塞的问题；正常中文跨页和分批到达保持完整。
- 命令输出按已到达的数据及时读取，避免小段输出等待读取缓冲区填满或进程退出后才更新。
- SFTP 内容比对及续传拒绝 FIFO 等特殊文件，避免阻塞读取或误判为已完成文件。
- 将命令输出分页边界处理拆成独立模块，增加非法字节、跨页中文和分批中文回归检查。
- 新增统一完整回归入口 `scripts/check-all.py`，保存逐项日志及 JSON 结果；修正集成测试硬编码 Debug、旧应用路径和架构的问题。
- 增加真实 XQuartz 窗口测试，验证默认关闭、不可信/可信 X11 转发和关闭通道后的窗口清理。
- README、Codex 接入指南及项目规范同步支持中英文，历史说明保留原文并增加英文摘要和导航。

默认仍为只读 Codex 接入，SSH 执行需单独授权。保留已有配置与凭据。完整回归范围与未验证环境见仓库 `docs/TESTING.md` 及 `docs/REVIEW-2.0.md`；不宣称所有环境或所有代码路径均已覆盖。

## English

- Consolidates existing SSH/local terminals, tree groups, tab reordering, recursive/batch SFTP, trzsz/ZMODEM, themes, credentials, history and Codex integration with a cross-module regression review.
- Fixes stalled Codex output pagination on consecutive malformed UTF-8 bytes, which could block subsequent commands at the complete-output gate. Chinese text remains intact across pages and incoming chunks.
- Reads arriving command output promptly instead of waiting for a buffer to fill or the process to exit.
- Rejects special files such as FIFOs during SFTP content comparison and resume, avoiding blocked reads or false completion.
- Separates output-page boundary handling into a focused module, with regressions for malformed bytes and split Chinese characters.
- Adds `scripts/check-all.py` for serial full-suite execution with individual logs and JSON results; fixes hardcoded Debug, application-path and architecture choices in integration checks.
- Adds real XQuartz window checks for disabled, untrusted and trusted X11 forwarding and channel-exit cleanup.
- Updates the user guide, Codex guide and contributor workflow in Chinese and English; preserves historical notes with English summaries and navigation.

Codex access remains read-only by default; SSH execution requires separate authorization. Existing configuration and credentials are preserved. See `docs/TESTING.en.md` and `docs/REVIEW-2.0.md` in the repository for scope and unverified environments; this is not a claim of complete code-path or environment coverage.

## 安装 / Installation

打开 DMG，将 MyTerm 拖入“应用程序”并替换旧版。升级前可导出加密偏好设置备份。
Open the DMG and replace MyTerm in Applications. You can export an encrypted preferences backup before upgrading.

临时签名，未使用 Developer ID 签名或 Apple 公证。本包不包含用户凭据或个人配置。
Ad-hoc signed, without Developer ID signing or Apple notarization. No user credentials or personal configuration are included.
