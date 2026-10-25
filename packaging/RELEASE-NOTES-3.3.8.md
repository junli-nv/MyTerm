# MyTerm 3.3.8

## 简体中文

- SSH 接入 Codex 支持按集群组织对话：选择或新建集群，继续已有对话，或创建自定义名称的对话（默认“日常运维”）。
- 使用 Codex 正式 app-server 接口创建、命名和读取对话；名称保存在 Codex，集群使用稳定工作目录，更换头节点或重连不会改变分类。恢复时重新授权并关联当前 SSH。
- 新对话默认不加日期；同名时追加日期和时分秒，极短时间内再次重名时精确到毫秒，不使用数字编号。继续对话保持原名。
- 保留全部历史的原生恢复入口；不自动迁移旧对话，不承诺自动创建 Codex 桌面端的项目侧栏条目。此版本集群索引暂不纳入偏好备份。
- 阻止在多个 MyTerm 标签中重复打开同一个集群对话；取消准备后不自动打开标签。中英文界面与文档同步。

## English

- Organize SSH-linked Codex conversations by cluster: select or create a cluster, continue a conversation, or create a named one (default: Daily operations).
- Official Codex app-server APIs create, name and read conversations. Names persist in Codex; clusters use stable working directories independent of SSH reconnections or head-node changes. Resuming binds fresh authorization to the selected SSH session.
- New names omit dates unless duplicated; collisions append date and time with seconds, then milliseconds for a same-second collision. No numeric suffixes; resumed names remain unchanged.
- The native all-history picker remains available. Existing chats are not migrated automatically; automatic desktop project-sidebar creation is not promised. The cluster index is not included in preferences backups in this version.
- Prevent opening the same cluster conversation in multiple MyTerm tabs; cancellation prevents a pending preparation from opening a tab. Chinese/English UI and documentation updated together.
