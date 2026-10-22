# MyTerm 3.3.5

## 简体中文

- 内置 Codex 标签不再强制使用 `--no-alt-screen`，尊重 Codex 保存的显示设置；不宣称已解决持续输出时的随机历史跳转。
- SFTP 下载及目录内文件冲突支持覆盖、跳过、全部覆盖和全部跳过；保留中断续传的临时文件与校验机制。文件承诺回调目标已存在时也使用该流程，不因普通冲突断开连接。
- ZMODEM 下载先暂存，完成后提示原名覆盖或跳过；保留的部分文件可选择续传或重新下载。上传默认覆盖，并保留明确的续传选择。续传前需确认源文件没有变化。
- 已知限制：Finder 接收文件承诺时可自行改名；需要原名覆盖/续传请使用 SFTP 面板下载按钮。trzsz/tsz 是独立协议，本次未修改其同名策略。

## English

- Embedded Codex tabs no longer force `--no-alt-screen`; saved Codex display settings apply. Random history jumps during ongoing output are not claimed fixed.
- SFTP download conflicts, including recursive children and existing file-promise destinations, offer overwrite/skip/all choices without disconnecting on ordinary conflicts. Resume temporary files and validation remain intact.
- ZMODEM downloads receive into staging before prompting to overwrite or skip the original name. Retained partial files can be resumed or restarted. Uploads default to overwrite with an explicit resume choice. Confirm that source files have not changed before resuming.
- Known limits: Finder can rename file-promise destinations; use the SFTP panel download action for original-name overwrite/resume. trzsz/tsz is a separate protocol whose conflict policy is unchanged.
