# MyTerm 3.4.8

## 简体中文

- Codex SSH 标签新增 `upload_items` / `download_items`，通过关联 SSH 的现有 SFTP 通道传输多文件和递归目录，保留空目录与隐藏文件。支持明确的跳过/覆盖策略和排除规则，不删除目标中多出的文件。
- `transfer_status` 返回阶段、整体/当前文件字节进度、实际传输字节、平均速度、续传偏移及有界失败清单；`cancel_transfer` 可取消。相同来源与目标可在校验匹配后续传，连接配置身份不依赖临时 SSH socket 路径。源文件或续传元数据不匹配时明确拒绝。
- 每次文件传输使用当前执行授权并消耗一个额度，且在 MyTerm 审批栏单独确认；命令“始终允许”不会隐式授权本地文件读写。传输受当前执行超时与剩余授权时间限制。只读关联不能传输。
- 首次右键直接粘贴会明确激活应用、窗口及终端，补充旧测试遗漏的键盘输入窗口断言。
- 滚动诊断增加手势增量、阶段、惯性、前后视口、历史行数/裁剪/清空计数；不记录终端文字。持续输出时的真实 Codex 跳顶尚未复现，不能视为已修复。

## English

- Add `upload_items` / `download_items` to Codex SSH tabs for multiple files and recursive directories over the associated SSH transport's SFTP subsystem, preserving empty directories and hidden files. Explicit skip/overwrite policies and exclusions never delete destination-only files.
- `transfer_status` reports phase, aggregate/current-file byte progress, actual transferred bytes, average speed, resumed offsets and bounded failures; `cancel_transfer` cancels work. Matching sources/destinations can resume after validation; connection identity is independent of transient SSH socket paths. Source or metadata mismatches are rejected.
- Every transfer uses active execution authorization and one allowance, with separate confirmation in MyTerm's approval bar. Command Always Allow does not implicitly authorize local file access. Current execution timeout and remaining authorization also bound transfers. Read-only associations cannot transfer files.
- Direct first-right-click paste explicitly activates the app, window and terminal; regressions now assert the keyboard window state omitted by earlier checks.
- Scroll diagnostics add deltas, gesture/momentum phases, before/after viewport, history rows, trimming and clear counts, without terminal text. The reported real Codex jump during streaming has not been reproduced and is not claimed fixed.

## 验证与已知限制 / Validation and known limitations

- 39 项核心检查，以及 Debug、Release、实际 DMG 副本和安装版窗口检查通过；真实 SSH/SFTP 双向传输、进度、取消及非零偏移续传检查通过。
- 完整 Release 回归的 8 个套件中，7 个通过（包含单独补跑的 SSH 执行/传输套件）。Codex CLI 代理端到端夹具未通过：独立配置目录复测时仍未观察到合成 HTTP 代理连接，CLI 报告网络重连错误，原因尚未确认；不能宣称完整回归全绿。
- 持续输出时双指上翻跳顶仍待现场复现；本版增加诊断，不宣称修复。物理设备/应用切换、Intel、X11 以及所有生产网络环境未全面验证。

- All 39 core checks and window checks in Debug, Release, an actual DMG copy and the installed app passed. Real SSH/SFTP bidirectional transfers, progress, cancellation and nonzero-offset resume passed.
- Seven of eight full Release suites passed, including the separately rerun SSH execution/transfer suite. The Codex CLI proxy end-to-end fixture failed: isolated-home retests still observed no connection to the synthetic HTTP proxy, and the CLI reported network reconnect errors. The cause is unresolved; the complete regression is not all green.
- Streaming trackpad jumps remain unreproduced in field conditions; this release adds diagnostics rather than claiming a fix. Physical-device/app-switching behavior, Intel, X11 and every production-network environment have not been exhaustively verified.
