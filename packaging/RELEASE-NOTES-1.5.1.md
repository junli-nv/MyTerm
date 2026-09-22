> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.5.1)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.5.1).

# MyTerm 1.5.1（Build 123）

- SSH 密钥管理显示关联服务器、保存会话、已打开标签和各级跳板机，支持展开用户目录和符号链接路径匹配。
- 删除被引用的密钥时列出受影响会话，并要求额外确认；取消任意一次确认都会保留密钥。
- 删除前重新检查关联信息，确认期间出现新引用时停止删除，避免误删。
- 完善中英文关联提示和长会话名称的换行、滚动显示。

关联统计覆盖应用内显式设置的密钥路径，不包含外部程序或 SSH 配置文件的隐式引用。删除应用内密钥副本不会修改会话配置或原始导入文件。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
