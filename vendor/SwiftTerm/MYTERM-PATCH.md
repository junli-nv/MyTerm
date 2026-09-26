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
