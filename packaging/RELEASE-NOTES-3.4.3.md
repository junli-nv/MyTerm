# MyTerm 3.4.3

## 简体中文

- 移除内嵌 SFTP 内容的固定最大宽度，背景随面板铺满，避免拉宽后露出透明区域。
- 处理 SFTP 顶部重复安全区域，保留终端主题透明度与独立窗口功能。
- 增加面板扩大超过 520 pt、缩小、模拟实时调整期间及结束后的边缘透明度回归检查。
- 修复终端延迟调整尺寸时右侧留白被错误扣除的问题；按实际裁剪视口绘制背景，保持原生 1 pt 分隔线。回归检查覆盖终端留白、分隔线及 SFTP 边缘。

## English

- Remove the inline SFTP content width cap and fill its allocated pane to avoid transparent margins when widened.
- Handle the duplicated top safe area while preserving terminal opacity and detached windows.
- Check panel edge opacity when expanding beyond 520pt, shrinking, during simulated live resize and after completion.
- Fix terminal gutter exclusion during debounced sizing: paint against the actual clip viewport and retain the native 1pt divider. Regression checks cover terminal gutters, divider and SFTP edges.
