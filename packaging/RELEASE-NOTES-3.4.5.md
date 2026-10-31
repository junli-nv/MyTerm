# MyTerm 3.4.5

## 简体中文

- SSH 标签提供端口转发状态与逐条启停；规则在认证后开启，单条失败不关闭 SSH。开关只作用于当前连接，重连恢复保存规则。
- 内置 Codex 标签不再受到全屏触摸板快速/按页偏好的影响；切换屏幕和滚动路由时清理残余滚动量。保留 Codex 显示配置，历史跳转仍需实际长时间输出验证。
- 补充鼠标路由诊断、真实 SSH 转发与滚轮回归，更新中英文说明。

## English

- SSH tabs expose per-rule forwarding status and controls. Rules start after authentication; a rule failure preserves SSH. Switches affect only this connection and reset to saved rules on reconnect.
- Built-in Codex tabs bypass full-screen Fast/Page trackpad preferences; screen and routing changes reset fractional motion. Codex display configuration remains untouched. Extended real-output scroll jumps still need field validation.
- Add mouse-routing diagnostics and real SSH forwarding/wheel regressions, with matching bilingual documentation.
