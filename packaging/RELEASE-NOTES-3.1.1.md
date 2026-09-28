# MyTerm 3.1.1

## 简体中文

- Codex SSH 执行支持多行脚本、LF 换行和 Tab 缩进，保留 4096 UTF-8 字节上限。
- 整段脚本原样提交审批和执行，计为一次请求；授权、超时与完整输出读取规则保持不变。
- 增加多行循环、heredoc、中文、标准输出/错误和退出码的真实 SSH 回归检查。

## English

- Codex SSH execution now accepts multiline scripts with LF newlines and tabs, retaining the 4096 UTF-8 byte limit.
- Approval and execution preserve the entire script as one request; authorization, timeout and complete-output rules remain unchanged.
- Add real SSH regression coverage for multiline loops, heredocs, Unicode, stdout/stderr and exit codes.
