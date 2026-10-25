# MyTerm 3.3.9

## 简体中文

- Codex 启动页支持移除本地对话记录、删除集群及其关联。操作需确认，不删除 Codex 历史、SSH 配置或目录文件；打开中的对话需先关闭标签。
- 明确说明 MyTerm 列表是独立索引，在 Codex 中删除对话不会自动删除本地记录。
- 支持选择新集群存储目录或恢复默认；已有集群保留原工作路径，避免影响恢复。展示当前集群目录。
- 兼容旧版集群索引；同步更新中英文界面、文档和回归测试。

## English

- Remove local conversation entries or clusters and their associations from the Codex launch page, with confirmation. Codex history, SSH configurations and project files are preserved; close open conversation tabs first.
- Explain that MyTerm maintains an independent index: deleting a conversation in Codex does not automatically remove its local entry.
- Choose a directory for new clusters or restore the default. Existing clusters keep their original working paths to preserve resume behavior; the current cluster directory is shown.
- Backward-compatible catalog loading, with matching Chinese/English UI, documentation and regression tests.
