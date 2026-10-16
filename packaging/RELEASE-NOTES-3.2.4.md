# MyTerm 3.2.4

## 简体中文

- 新增默认关闭的终端诊断：限时、限量的内存事件记录、问题时间标记及元数据 ZIP 导出；不采集终端正文或凭据。
- 修复选中后恢复输入时输出跟随可能仍暂停的问题。
- 修复组合输入结束后残留状态影响后续增强键盘 Enter 编码的问题；普通英文“双回车”反馈尚未确认根因。

## English

- Add opt-in terminal diagnostics with bounded in-memory captures, incident markers, and metadata-only ZIP export; no terminal text or credentials are collected.
- Resume output following when input resumes after selection, even if the caret remains visible.
- Clear stale composition state that could affect enhanced Enter encoding; the reported ordinary-English double-Enter issue remains unconfirmed.
