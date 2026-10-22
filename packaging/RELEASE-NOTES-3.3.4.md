# MyTerm 3.3.4

## 简体中文

- 撤回 3.3.3 对内置 Codex 普通缓冲区的强制滚动接管，恢复按终端鼠标报告模式路由滚动；保留设置窗口跟随当前桌面的行为。
- 修复 SFTP 批量拖拽下载文件/目录时，先前任务失败关闭连接后，后续排队任务访问已关闭管道导致应用崩溃。关闭操作可重复调用，关闭后的请求返回错误；新增队列失败及重连回归测试。
- Codex 持续输出时的历史随机跳转仍为已知问题，本次回退不代表该问题已解决。

## English

- Revert the forced local scrolling override for embedded Codex normal buffers introduced in 3.3.3. Scroll routing again follows terminal mouse-reporting mode. Settings windows still follow the active desktop.
- Fix an application crash during queued SFTP file/directory drag downloads when an earlier failed task closed the connection and a later task accessed a closed pipe. Closing is idempotent and requests on closed clients return errors. Add failed-queue and reconnection regression checks.
- Random history jumps during continued Codex output remain a known issue; reverting the override does not establish that the issue is resolved.
