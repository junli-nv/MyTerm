> 历史版本说明：内容仅适用于此版本。当前用法见 [中文指南](../README.md)；[本版本英文摘要](../CHANGELOG.en.md#version-1.4.8)。
> Historical release notes: details apply only to this version. See the [current English guide](../README.en.md) and [English summary](../CHANGELOG.en.md#version-1.4.8).

# MyTerm 1.4.8

- 全屏程序（含 tmux/less）复制默认保留屏幕行，避免重绘造成的折行标记将多行合并。
- 选中自动复制、⌘C 和右键复制使用同一规则；普通 shell 的自动折行仍按原规则合并。
- 新增「复制（合并自动折行）」菜单，可通过 Shift+右键访问，适用于需要拼接全屏程序长行的场景。
- 加入真实 tmux/less 翻页、回翻、搜索和缩放输出回放，以及空行、中文和反向选区回归检查。
