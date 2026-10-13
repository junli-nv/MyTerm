# MyTerm 3.1.7

## 简体中文

- 标签单击选中后即可右键打开菜单，无需先双击；支持 Control+单击。
- 保留标签拖拽排序、关闭按钮和空白处双击最大化行为。

## English

- Open tab menus with right-click or Control-click after a single selection, without double-clicking first.
- Preserve tab dragging, close buttons and double-clicking blank strip space to maximize.

## 多 Codex 会话 / Multiple Codex sessions

同一个 SSH 标签可以关联多个 Codex 标签。每个 Codex 标签的授权时长、命令额度、审批模式、执行记录和输出读取进度独立；启动、续期、停止或关闭其中一个，不会替换其他标签的授权。已批准的命令按提交顺序串行使用同一 SSH 执行通道；`queued` 表示已批准、正在等待，无需重复提交或重新授权。关闭 SSH 标签或连接断开会使所有关联执行授权失效。外部 MCP 默认仅能读取已共享会话，不能借用内置 Codex 标签的执行授权。

One SSH tab can be associated with multiple Codex tabs. Each Codex tab has independent authorization duration, command budget, approval mode, records and output delivery progress. Starting, renewing, stopping or closing one does not replace another tab's authorization. Approved commands run serially on the same SSH transport in submission order; `queued` means approved and waiting, with no need to resubmit or re-authorize. Closing or disconnecting SSH invalidates all associated execution grants. External MCP clients can read shared sessions but cannot borrow an internal Codex tab's execution authorization.
