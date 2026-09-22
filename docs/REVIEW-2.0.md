# MyTerm 2.0 审查与验证 / Review and validation

本文件记录 2.0（Build 143）的发布审查，不作为后续版本的测试结果。
This is the release review for 2.0 (Build 143), not evidence for later versions.

## 审查结论 / Review findings

对第一方代码结构、协议与持久化边界、进程/计时器关闭路径、异步连接身份、输出分页、递归传输和现有回归入口进行审查。SwiftTerm 重点检查 MyTerm 修改与终端回归，不将此次工作表述为整个上游库的逐行安全审计。

Reviewed first-party structure, protocol/persistence boundaries, process/timer shutdown, asynchronous connection identity, pagination, recursive transfers and regression entry points. SwiftTerm review focuses on MyTerm modifications and terminal regressions, not a line-by-line security audit of the entire upstream library.

| 发现 / Finding | 处理 / Resolution |
| --- | --- |
| 连续非法 UTF-8 字节使命令分页游标不前进 / Consecutive invalid UTF-8 bytes stall pagination | 可复现：4096 个 `0x80` 字节返回偏移 0。提取 `CommandOutputPage`，仅为有效的不完整字符延后边界，非法字节仍前进。 / Reproduced with 4096 bytes of `0x80` returning offset 0. A focused page-boundary helper defers only valid incomplete characters. |
| 小段运行中输出等待缓冲区或退出 / Small output waits for buffer fill or exit | 使用可中断的 POSIX 管道读取；两字节中文前缀与受控后续字节验证及时读取及字符完整性。 / Use interruptible POSIX reads; a controlled split-character fixture verifies prompt delivery and character integrity. |
| SFTP 同名特殊文件进入普通文件比对或续传 / Special files reach regular-file comparison or resume | 对 FIFO 等特殊目标及续传文件提前拒绝，测试要求及时失败、保留文件并保持连接可用。 / Reject special targets and partial files before opening; regressions require prompt failure, preserved files and a usable connection. |
| SFTP 界面测试偶发未就绪 / SFTP UI fixture occasionally not ready | 发布被单击断言拦截，同一包独立复测通过；以表格数据、可见尺寸及关键窗口状态代替固定 100 毫秒等待，不跳过点击断言。 / A click assertion blocked packaging; isolated rerun passed. Replaced a fixed delay with data/layout/key-window readiness, retaining the click assertion. |
| 集成测试硬编码旧应用、Debug 或 arm64 / Tests hardcode old app, Debug or arm64 | 使用显式应用/配置和本机架构；完整回归入口串行执行、保存日志、退出码及二进制身份。 / Honor explicit app/configuration and host architecture; the runner serializes suites and records logs, status and binary identity. |

保留现有分层和手势/数据修改分离。`MyTermApp`、`CodexBridge` 仍是较大的编排文件，后续功能宜继续提取专注模块；本次未进行无行为收益的大规模改写。不能通过一次审查保证代码永远可维护或不存在缺陷。

Existing layering and gesture/data separation are preserved. `MyTermApp` and `CodexBridge` remain larger orchestration files; future additions should favor focused modules. No broad rewrite without a behavioral benefit was undertaken. One review cannot guarantee permanent maintainability or absence of defects.

## 验证环境 / Environment

macOS 26.7 (25G229), Apple Silicon arm64, Apple Swift 6.4, [XQuartz 2.8.6](https://www.xquartz.org/). XQuartz 官方安装包签名及公证检查通过；使用本机临时 sshd 和测试密钥，不修改用户 SSH 配置。

XQuartz's official installer signature and notarization were verified. SSH checks use temporary loopback daemons and fixture keys, without editing user SSH configuration.

## 验证结果 / Results

- Debug：9 项完整套件通过；最终 SFTP 补充后再次通过 23 组核心检查及打包阶段的 Debug 窗口检查。 / Nine full Debug suites passed; final SFTP additions were rechecked by all 23 core groups and packaging's Debug window checks.
- Release：9 项套件全部通过，包括 23 组核心检查、真实 SSH/tmux、完整窗口、ZMODEM、trzsz、密码更新、Codex 代理、独立 SSH 执行与真实 X11。 / All nine Release suites passed, including 23 core groups, real SSH/tmux, complete windows, transfers, password rotation, Codex proxy/execution and real X11.
- Python 编译、Shell 语法、C 代理静态分析和 Markdown 相对链接检查通过。 / Python compilation, shell syntax, C proxy static analysis and Markdown relative-link checks passed.

- DMG 验证、实际 DMG 复制件和安装后窗口检查全部通过；19 项包内容比较一致，签名检查通过。安装版与 `dist/MyTerm.app` 相同，安装路径已重新启动。 / DMG verification, window checks on a copy from the actual DMG and the installed app passed. All 19 bundle entries match and signatures verify. The installed app matches `dist/MyTerm.app` and was reopened from its installed path.

Release 可执行文件 SHA-256 / Release executable SHA-256:

`c5b5d506e752623f0ac72088c57c493a9a120a01b8da2c77a5e6eeac07557ce3`

独立套件耗时（秒） / Release suite durations (seconds):

| Suite | Result | Seconds |
| --- | --- | --- |
| core | PASS | 4.04 |
| ssh-integration | PASS | 11.83 |
| window-controls | PASS | 35.43 |
| zmodem | PASS | 2.6 |
| trzsz | PASS | 16.62 |
| password | PASS | 0.72 |
| codex-proxy | PASS | 0.83 |
| codex-execution | PASS | 0.67 |
| x11 | PASS | 1.81 |


## 范围与限制 / Scope and limits

功能对应表及复现入口见 [中文测试指南](TESTING.md) / [English testing guide](TESTING.en.md)。这不是 100% 行/分支覆盖率声明，也不是所有组合或远端实现的穷举测试。

- Codex 登录衔接、代理和执行协议通过模拟/本机真实进程验证，没有消耗真实模型请求或验证付费账号额度。 / Login continuation, proxy and execution protocols use fixtures and real local processes; paid-account quotas and live model requests are not tested.
- X11 使用真实 XQuartz、生产 SSH 参数及 xmessage 窗口，不能替代所有远端图形应用和 GPU 加速测试。 / Real XQuartz windows and production SSH arguments do not validate every graphical application or GPU path.
- 未在 Intel、最低 macOS、真实公网丢包环境或全部硬件密钥上验证。 / Intel, minimum macOS, public-network loss and all hardware keys are not validated.
- 程序化界面检查不替代所有 Finder/输入设备/会议软件人工验收；短时进程回收不证明长期无内存泄漏。 / Programmatic UI checks do not replace all Finder/device/conferencing acceptance; short cleanup tests cannot prove long-term leak freedom.
