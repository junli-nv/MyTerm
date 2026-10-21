# MyTerm 3.3.3

## 简体中文

- 设置、Codex 接入和 SSH 配置窗口打开时移动到当前桌面，避免激活旧窗口时跳转到其他桌面。
- 内置 Codex 标签在普通终端缓冲区中的滚轮/触摸板滚动由 MyTerm 处理，不再因程序开启鼠标上报而交给 Codex。上翻阅读时输出继续，回到底部后恢复跟随；全屏程序仍使用原有鼠标路由。历史仍受行数和内存预算限制。
- 已知问题：Codex 持续输出时，上翻历史仍可能突然跳到更早内容，用户复测确认本次调整未解决该问题，后续继续排查。

## English

- Settings, Codex integration and SSH configuration windows move to the active desktop when opened instead of activating a window on another desktop.
- In embedded Codex tabs, MyTerm handles wheel/trackpad scrolling in the normal terminal buffer even when the process enables mouse reporting. Output continues while reading history; scrolling back to the bottom resumes following. Alternate-screen applications retain their mouse routing. History remains subject to line and memory limits.
- Known issue: scrolling through history while Codex continues producing output can still jump unexpectedly to much earlier content. User testing confirmed that this change does not resolve the issue; further investigation is pending.
