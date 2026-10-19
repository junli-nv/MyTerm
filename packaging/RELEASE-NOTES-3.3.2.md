# MyTerm 3.3.2

## 简体中文

- 同地址会话的 OpenSSH 导出别名改为 myterm-session-名称-短编号，便于区分直接登录入口与公共跳板；保留别名冲突保护，纯中文名称回退使用主机地址，完整名称保留在注释中。

## English

- OpenSSH export aliases for sessions sharing a host now use myterm-session-name-short-id, distinguishing direct login entries from shared jumps. Collision protection remains; names without ASCII characters fall back to the host, with full names retained in comments.
