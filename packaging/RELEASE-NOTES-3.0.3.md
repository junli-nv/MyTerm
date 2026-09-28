# MyTerm 3.0.3

## 简体中文

- 修复修改 SSH 名称、日志、压缩或转发等配置后重复要求输入已保存密码的问题。
- 自动迁移可匹配的旧凭据记录，保留自定义密码名称；已保存密码被拒绝时仍提示更新。
- 保留主机、用户、端口与跳板路径的凭据隔离，补充密钥配置编辑和真实 SSH 密码认证回归测试。

## English

- Preserve saved passwords when editing SSH names, logging, compression, forwarding and other unrelated settings.
- Migrate matching legacy credentials while retaining custom names; rejected passwords still prompt for replacement.
- Keep endpoint and jump-route credential isolation, with regression checks for key configuration edits and real SSH password authentication.
