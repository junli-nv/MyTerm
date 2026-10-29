# MyTerm 3.4.2

## 简体中文

- 修复标签栏与终端之间分隔线可能透出底层窗口的问题，使用单物理像素实线和不透明背景，避免双线观感。
- 保留终端主题透明度设置；增加本地和 SSH 标签切换后的分隔线像素透明度检查。

- 去除嵌套分屏重复的标题栏安全区域，消除标签栏到终端间的透明空隙；关闭系统附加分隔线。

## English

- Render the tab/terminal separator as a single physical pixel with opaque backing, avoiding both see-through seams and a double-line appearance.
- Preserve terminal theme opacity; check separator pixel opacity for both local and SSH tabs.

- Remove duplicated titlebar safe-area insets in nested splits and disable the extra system separator. Verify geometry with sidebar/SFTP open as well as local/SSH tabs.
