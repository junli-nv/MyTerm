# MyTerm 3.4.10

## 简体中文

- 修复 tmux 复制模式翻页／滚动重绘后，再次双击只能选择一个屏幕行的问题。明确选择逻辑行时，按满行、样式及边框推断连续性，并清除逻辑行末尾由重绘产生的空格填充；不修改终端内容或折行标记。
- 空白分隔涵盖制表符、Unicode 空白、盲文空白与韩文填充字符，保留 emoji 连接符和宽字符完整性。
- 保留真实隔离 tmux 输出的完整操作回归：翻页／滚动、选词、再选逻辑行、剪贴板、屏幕分行复制、远端鼠标与 Shift。增加短行、窗格／表格边框及状态行反向检查。
- 把原先仅 Debug 的鼠标选项、字体／历史持久化和分组交互检查接入 Debug／Release／DMG 共用入口；完整回归报告记录失败、阻塞与未执行项，可继续独立套件。
- 新增双语交互覆盖矩阵与完整复现测试规则。全屏坐标重绘无法区分所有恰好满行的硬换行；保留“复制（保留屏幕换行）”，不宣称所有用户配置和实体设备已经验证。
- 修复共用窗口检查的主队列等待互锁；代理测试明确选择应用默认 CLI，避免 PATH 包装脚本覆盖测试环境。HTTP／SOCKS5 合成检查通过，不修改用户脚本。
- 开始页、关于面板及会话冒烟检查也覆盖 Release／实际 DMG。一次 Release SSH 重连退出检查超时，随后带诊断的连续六次检查通过，根因尚未确认，不宣称已修复该间歇现象。
- Debug、Release 各 10 个完整自动套件通过（含 X11），实际 DMG 副本的窗口、开始页冒烟、MCP、签名及包内容比对通过；同一选择测试在 3.4.9 失败、修复版通过。实体触摸板、用户 tmux 配置、Intel 及最低支持 macOS 仍需现场验证。

## English

- Fix repeated double-click selecting only one visual row after tmux copy-mode paging/scroll redraws. Explicit logical-row selection infers continuity from full rows, styles and borders, removing redraw padding at logical-row ends without changing terminal contents or wrap flags.
- Whitespace token boundaries include tabs, Unicode whitespace, Braille blank and Hangul fillers while preserving emoji joiners and wide characters.
- Retain the complete interaction using real isolated tmux output: paging/scrolling, token selection, logical selection, clipboard, screen-row copy, remote mouse and Shift. Add negative checks for short rows, pane/table borders and status lines.
- Move formerly Debug-only mouse options, font/history persistence and group interactions into the shared Debug/Release/DMG window suite. Full regression summaries record failures, blocked and pending suites, with optional independent-suite continuation.
- Add bilingual coverage matrices and complete-reproduction testing rules. Coordinate redraws cannot disambiguate every exact-width hard break; keep Copy with Screen Line Breaks and report user-configuration/device gaps.
- Fix the shared window-check main-queue wait deadlock; choose the app-default CLI explicitly for proxy fixtures, avoiding PATH wrappers overriding the test environment. Synthetic HTTP/SOCKS5 checks pass without changing user scripts.
- Welcome-page, About-panel and session smoke also cover Release/actual DMG. One Release SSH reconnect/exit check timed out; six subsequent diagnostic runs passed. Its cause remains unconfirmed and this intermittent occurrence is not claimed fixed.
- All 10 full automated suites passed in both Debug and Release, including X11. The actual DMG copy passed window, startup-smoke, MCP, signature and bundle-content checks. The identical selection test fails on 3.4.9 and passes with this fix. Physical trackpad, user tmux configurations, Intel and minimum-supported macOS still require field validation.
