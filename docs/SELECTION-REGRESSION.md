# 终端交互回归矩阵

简体中文 · [English](SELECTION-REGRESSION.en.md) · [完整回归指南](TESTING.md)

本文是覆盖清单，不表示所有组合均已通过。以测试日志中的应用与构建配置为准。完整检查接入 `window-controls-check.py`，打包时覆盖 Debug、Release 和实际 DMG 副本；`--smoke-test --window-controls-check --terminal-copy-only` 可单独执行剪贴板检查。检查保存并恢复剪贴板，偏好测试使用隔离存储。

| 交互／选项 | 自动检查证据 | 仍存在的边界 |
| --- | --- | --- |
| 首次双击选词、再次双击逻辑行、快速四击 | `TerminalCopyCheck`：普通／备用缓冲区、标点／URL、中文、每个折行位置 | 实体设备与点击时序差异 |
| tmux 复制模式连续两次上翻、下翻、逐行上下滚动 → 首次／再次双击 → 复制／跨记录行拖选 | `TerminalSelectionCheck` 回放隔离真实 tmux 输出，断言词、整条记录、剪贴板、屏幕分行复制及缓冲区不变 | 用户 tmux 配置、嵌套窗格、不同版本和实体按键／触摸板 |
| 原生软折行（含空白／宽字符边缘）、坐标重绘的宽字符边缘空格、硬换行、旧折行标记、恰好满行的硬换行 | `TerminalCopyCheck`：精确剪贴板与行选择检查 | 坐标重绘后，无法区分所有恰好满行的硬换行与软折行 |
| 坐标重绘的短行、窗格／表格边框、不同样式状态行 | `TerminalSelectionCheck`：不得合并独立行 | 无边框窗格与相同样式仍有歧义；兜底只用于明确的选词／逻辑行选择 |
| 22 种渲染后的分隔符：ASCII 空格／制表符、Unicode 间隔字符（含不换行／欧甘／数字／en／em／细／发丝／数学／全角空格）、盲文空白与韩文填充字符 | `TerminalSelectionCheck`：检查渲染后的左右词、空白格及宽字符续格 | 字体相关的字形差异；不可见格式控制符不自动视为分隔符 |
| 中文、宽字符、emoji 连接符／字素 | `TerminalCopyCheck`、`TerminalSelectionCheck` | 未穷举全部 Unicode、字体及组合序列 |
| 远端鼠标所有权／Shift 本地选择 | `TerminalCopyCheck`、`TerminalPasteCheck` | 各远端 TUI 的所有鼠标协议 |
| 自动复制开关、右键粘贴开关、Shift 菜单、持久化 | `MouseInteractionCheck`、`TerminalPasteCheck`；接入共用 Release／DMG 检查，原先部分仅 Debug | 实际应用切换及首次事件交付 |
| 禁用终端响铃 | `MouseInteractionCheck`：默认值与偏好重载 | 实际声音仍需按设备／系统音量人工确认 |
| 持续输出时选择、恢复跟随输出 | `TerminalCopyCheck`、`TerminalScrollCheck` | 长时间负载及系统事件调度 |
| tmux／less 翻页、搜索、缩放重绘后复制 | `TerminalCopyCheck`：真实输出回放、独立文本预期 | 各种分页器及配置 |
| 字体缩放／重排、Ctrl 滚轮 | `TerminalCopyCheck`、`FontZoomKeyboardCheck`、`MouseInteractionCheck` | 显示器缩放与实体手势 |
| 标准／快速／按页滚动、反向／惯性、Codex 隔离 | `FullscreenScrollCheck`、`TerminalScrollCheck` | 实体设备加速度 |
| 阅读／滚动时 Codex CSI 3J 重放、超时及透明度 | `CodexReplayCheck` | 真实 CLI／模型负载及触摸板验收 |
| 字体／主题／历史持久化、分组对话框／拖放 | `AppearanceHistoryCheck`、`GroupNameDialogCheck`；接入共用 Release／DMG 检查，原先仅 Debug | 平台／字体可用性 |

## 保留复现

`python3 scripts/capture-tmux-copy-fixture.py --swift Sources/MyTerm/TmuxCopyModeFixture.swift` 使用独立 tmux 服务和合成记录，捕获增量终端字节。文本预期来自已知原始记录与 tmux 复制模式滚动偏移，独立于 MyTerm 解析器。禁止捕获用户已有窗格或私人输出。同一份测试在前一实现上必须失败，修复后必须通过；不能改成只断言屏幕上出现了文字。

兜底不更改缓冲区折行标记或输入字节，普通拖选与内置 Codex 滚动不受影响。全屏行可能缺少足够信息用于精确重建；应保留屏幕分行复制并记录边界，不能宣称已穷尽覆盖。
