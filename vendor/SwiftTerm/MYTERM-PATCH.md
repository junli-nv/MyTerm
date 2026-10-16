# MyTerm renderer extension

Source: https://github.com/migueldeicaza/SwiftTerm
Pinned revision: 5d14406844143538cd8f8851d2d8a67c1fe443e5 (previously resolved as 1.20.0).
MIT license is retained in LICENSE. Library sources and its build-info plugin are vendored; the manifest includes only targets needed by MyTerm.

The macOS renderer exposes an optional row foreground provider. The shared attributed-string builder applies its colors to temporary render attributes, preserving cell contents, the parser, selection, cursor, background, and raw attributes. The provider defaults to nil. No incoming/output bytes or buffer cells are rewritten. This narrow hook is shared by CoreGraphics and Metal text rendering.

The ANSI bright-bold mapping promotes only indices 0–7 for bold text. Explicit bright (8–15) and extended (16–255) palette indices remain unchanged when bright-bold is disabled.

- `Terminal.getHostSnapshot(screen:maximumRows:)` exports at most 1,000 rows on demand for the read-only Codex bridge. Uses existing logical-wrap text extraction, normal history or the visible buffer, without changing terminal state or scanning all scrollback.

- Codex 大范围历史分页：主程序快照接口允许最多 10,000 个显示行，按调用方上限冻结后分页传出；不改变渲染、PTY 或终端滚动历史设置。

- Expose macOS `keyDown(with:)` and `resignFirstResponder()` as open so MyTerm can translate the single command key following the default tmux Ctrl+B prefix through the ASCII-capable keyboard layout, without changing normal IME composition.

- PTY 生命周期：每次启动使用独立 generation；串行交付已读取数据后才继续读取，最多一个 128 KiB 读取任务；EOF 关闭 DispatchIO，等待数据交付和 waitpid 后才通知退出。显式停止丢弃旧回调，清除 PID 所有权，保留退出画面不再持有 PTY。后台后代仍持有 slave 时，shell 退出后最多额外排空 1 秒再关闭通道。
- PTY lifecycle: launch generations isolate late callbacks; one bounded 128 KiB read is rearmed only after delivery. EOF closes DispatchIO; exit notification follows output delivery and reaping. Explicit stop invalidates callbacks and PID ownership. Retained output no longer retains PTYs. Descendants retaining the slave get a one-second drain window after shell exit before channel cancellation.

- Expose the read-only `Terminal.isDisplayBufferAlternate` state and macOS `scrollWheel(with:)` as open for MyTerm’s full-screen trackpad speed and opt-in page navigation. The upstream default scroll algorithm remains unchanged.
- 公开只读 `Terminal.isDisplayBufferAlternate` 状态和 macOS `scrollWheel(with:)` 覆盖入口，供 MyTerm 全屏触摸板加速及可选按页导航使用；上游默认滚动算法不变。

- Sending input resumes normal-buffer output following even when selection paused scrolling with the caret still visible. Completed or empty IME preedit clears Kitty composition state before later keyboard-protocol negotiation. Expose macOS `keyUp` and `becomeFirstResponder` for opt-in metadata diagnostics; no key contents are recorded.
- 输入时即使光标仍在视口内，也解除选中文本造成的滚动暂停；组合输入提交或清空时重置 Kitty 组合状态。开放 macOS `keyUp` 和 `becomeFirstResponder` 供可选的元数据诊断使用，不记录按键正文。
