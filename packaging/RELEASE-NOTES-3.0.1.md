# MyTerm 3.0.1

Build 150 · Apple Silicon (arm64) · macOS 14 or later

## 中文

- 空分组提示支持窄侧栏换行，修正回归检查对界面语言的依赖。

- 支持终端焦点下 ⌘+ / ⌘= 放大、⌘- 缩小字体，每步 0.5 pt。

- 移除重复执行计划面板和计划记录工具，计划仅在 Codex 终端中展示；保留命令审批、停止及完整输出检查。

- 启动 Codex 时默认勾选允许执行 SSH 命令，实际命令仍需逐条确认；可取消勾选保持只读。

- 移除 SSH 标签右键菜单的“复制会话 ID（Codex）”；内部自动传入 ID，外部使用 `list_sessions` 查询已授权会话。

- 修复“启动 Codex 标签”会话选择弹窗未跟随界面语言的问题，弹窗打开时切换语言也会立即更新。
- 移除重复的 SSH 接入总开关；确认启动后自动授权所选 SSH 会话，未选择的会话不会开放。关闭最后一个关联的 Codex 标签或 SSH 标签时撤销读取权限。
- 移除设置中的独立“执行记录与控制”窗口入口，执行授权、审批与停止操作集中在对应 Codex 标签中。

## English

- Wrap empty-group hints in narrow sidebars and make regression checks independent of the selected interface language.

- Support ⌘+ / ⌘= to enlarge and ⌘- to shrink terminal fonts in 0.5 pt steps while the terminal has focus.

- Remove duplicate plan UI and plan recording; plans appear only in the Codex terminal. Preserve command approvals, stopping and complete-output checks.

- Enable SSH command execution in the startup chooser by default, retaining per-command approval and an optional read-only mode.

- Remove Copy Session ID (Codex) from the SSH tab menu. Internal tabs receive the ID automatically; external clients use `list_sessions` for authorized sessions.

- Make the Open Codex Tab session chooser follow the interface language, including changes while it is open.
- Remove the redundant SSH access switch. Confirming startup authorizes only the selected SSH session. Closing the last associated Codex tab or the SSH tab revokes read access.
- Remove the separate execution-history window from settings; manage authorization, approvals and stopping in the associated Codex tab.
