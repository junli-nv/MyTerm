# MyTerm 3.3.1

## 简体中文

- 跳板机管理支持密码输入和显示/隐藏，留空保留已有凭据；测试可使用未保存密码。

- OpenSSH 导出按有效连接参数合并重复跳板，使用包含名称和简短标识的可读别名，并列出引用会话。多级跳转顺序保持；代理、认证、压缩或调试设置不同的配置不会错误合并。

## English

- Add password entry and show/hide to Jump Host Manager. Blank preserves credentials; tests can use unsaved passwords.

- OpenSSH export deduplicates jump hosts by effective connection settings, uses readable aliases with names and short identifiers, and lists referencing sessions. Multi-hop order is preserved; different proxy, authentication, compression or logging settings remain separate.
