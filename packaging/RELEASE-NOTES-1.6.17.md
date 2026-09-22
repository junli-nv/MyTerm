> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.6.17)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.6.17).

## MyTerm 1.6.17（Build 142）

- 修复 SSH 异步初始化时右上角 SFTP 入口未及时显示的问题；SSH 标签从准备连接阶段起即提供入口，无需打开底栏。
- SFTP 已弹出独立窗口时，点击右上角入口将该窗口置前；内嵌状态仍可直接展开、收起。
- 本地标签不显示 SFTP 按钮，保持右上角固定位置，增加初始化前入口及不依赖底栏的回归检查。

Apple Silicon 版本，临时签名，未进行 Apple 公证。
