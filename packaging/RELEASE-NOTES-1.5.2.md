> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.5.2)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.5.2).

# MyTerm 1.5.2（Build 124）

- 修复 SSH 中输入星号后需等待下一个字符才显示的问题：立即显示可打印的星号，同时保留副本识别 ZMODEM 握手，避免重复输出。
- 保持跨数据包、逐字节到达的 ZMODEM 握手识别，覆盖普通文本和无效握手的回归检查。
- Debug 和 Release 均支持真实 ZMODEM 上传、下载及拖拽上传自检，校验文件内容一致。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
