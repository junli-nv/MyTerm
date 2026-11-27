# MyTerm 3.4.9

## 简体中文

- 收窄 Codex 提示词：只有用户明确要求在本机与远端之间复制文件/目录时才使用上传下载；远程开发默认通过已授权的 `execute_command` 直接在远端编辑和测试。远端脚本、here-document、补丁和文本写入不受跨机传输限制约束。
- 启动提示、MCP 初始化指令及工具描述使用共用策略，明确本地 CodexProjects 目录不是必须下载源码的工作副本，本地只读沙箱不等于已授权 SSH 只读。传输的单次确认、进度及续传机制继续保留。
- 两次用户诊断均显示 Codex 在普通缓冲区持续输出时发送 CSI 3J，清空历史并将视口归零。内置 Codex 标签在上翻阅读时会暂时保留可见画面与少量内容锚点，继续解析输出，在重绘匹配后恢复阅读位置，并保留期间的原生滚动行数。
- 内容无法匹配时保护最多两秒，随后回到最接近的可用位置；终端输入/点击、切换屏幕缓冲区会解除保护。不忽略真正的清空历史指令，也不更改普通 Shell/tmux 或 Codex 全屏鼠标协议。保护数据仅短暂存于内存，诊断只增加是否保护中的布尔状态，不导出画面或锚点文本。
- 真实触摸板体验仍需用户验收；此前 Codex 代理端到端检查失败尚未确认原因，本版不宣称解决。

## English

- Narrow Codex instructions: upload/download tools are only for explicitly requested copies between the Mac and SSH host. Remote development defaults to authorized `execute_command` edits/tests on the host. Remote scripts, here-documents, patches and text writes are not cross-machine file transfers.
- Share the scope across startup prompts, MCP initialization and tool descriptions. CodexProjects is not a required remote-source checkout, and the local read-only sandbox does not make authorized SSH execution read-only. Separate transfer confirmation, progress and resume remain available.
- Two user diagnostic captures show CSI 3J clearing normal-buffer history and resetting the viewport during streaming. Built-in Codex tabs now briefly hold the visible reading image and a small content anchor when reading above the bottom, continue parsing output, and restore the reading position after matching replay while preserving native wheel-row intent.
- An unmatched hold is bounded to two seconds, then uses the nearest available position. Terminal input/clicks and screen-buffer switches release it. Actual clears remain effective, and ordinary shells/tmux and fullscreen mouse protocols retain their behavior. Image/anchor data stays briefly in memory only; diagnostics add a holding flag without exporting images or anchor text.
- Physical trackpad behavior still needs field acceptance. The previously failing Codex proxy end-to-end check remains unresolved and is not claimed fixed.

## 验证 / Validation

- 39 项核心检查通过；Debug、Release、实际 DMG 副本和安装版窗口回归通过。覆盖 MCP 提示词范围、重绘的文字像素/透明度、重复清空、行数变化、继续滚动、真实两秒回退及普通 Shell 隔离。
- 真实 SSH/SFTP 双向传输、进度、取消和续传通过。一次既有 PTY 退出压力检查发生超时，重新完整运行后通过，保留了失败日志；未将此现象宣称为已修复。
- 安装后重开关联 Codex 标签以加载新提示词，可恢复原对话；外部 IDE 需要重载 MyTerm MCP。

- All 39 core checks and window regressions in Debug, Release, an actual DMG copy and the installed app passed, covering MCP prompt scope, replay text pixels/alpha, repeated clears, changed history lengths, continued scrolling, the real two-second fallback and ordinary-shell isolation.
- Real SSH/SFTP bidirectional transfer, progress, cancellation and resume passed. One existing PTY exit stress run timed out; a complete rerun passed and the failed log was retained. That occurrence is not claimed fixed.
- Reopen an associated Codex tab after installation to load the new instructions; the conversation can be resumed. External IDEs need to reload MyTerm MCP.
