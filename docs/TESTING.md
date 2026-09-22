# 测试与维护

简体中文 · [English](TESTING.en.md) · [README](../README.md)

## 完整回归入口

在仓库根目录运行。需要 macOS 图形会话、Swift、系统 OpenSSH/SFTP、Codex CLI、tmux、lrzsz，以及安装了 `scripts/requirements-password-test.txt` 的独立 Python 虚拟环境。缺少依赖会失败，不会静默跳过。

```bash
bash scripts/check.sh
bash scripts/build-app.sh debug /tmp/myterm-check/Debug/MyTerm.app
python3 scripts/check-all.py /tmp/myterm-check/Debug/MyTerm.app --configuration debug
```

`--password-python` 可指定密码测试的虚拟环境解释器，默认 `.test-venv/bin/python`。`--logs` 指定日志目录；默认在系统临时目录创建独立目录。逐项日志和 `summary.json` 保留退出码与耗时。失败立即停止，修复后重新运行失败项及受影响测试。图形检查串行执行，以免互相抢占窗口焦点；测试期间避免操作测试窗口。

Release 检查必须使用相应构建的核心测试程序和指定应用：

```bash
swift build --build-system native -c release --product MyTermChecks
bash scripts/build-app.sh release /tmp/myterm-check/Release/MyTerm.app
python3 scripts/check-all.py /tmp/myterm-check/Release/MyTerm.app --configuration release
```

安装并启动 XQuartz 后，加 `--x11` 可验证真实 X11 窗口（关闭、不可信及可信转发和连接退出清理）；未启用时 `summary.json` 会明确记录。也可单独运行 `python3 scripts/x11-check.py`，通过 `MYTERM_TEST_CONFIGURATION` 指定 Debug/Release。

也可将应用参数换为 `/Applications/MyTerm.app` 或从 DMG 复制的应用。此入口不会构建、安装、发布或修改 Release。不能用 `swift test` 替代：本项目核心回归由可执行目标 `MyTermChecks` 驱动。

## 功能与验证对应关系

| 功能 | 检查入口与范围 |
| --- | --- |
| 本地 Shell、PTY、退出、尺寸、Unicode | `MyTermChecks`、Debug smoke、窗口检查 |
| SSH 认证、别名、压缩、跳板、HTTP/SOCKS5、L/R/D 转发 | `integration-check.py`：临时本机 sshd、代理、回显服务及多级组合 |
| 密码首次保存、复用、拒绝与更新 | `password-check.py`：真实 OpenSSH askpass 和临时加密数据库 |
| 分组树、拖拽、会话恢复/导入导出 | 核心归档/分组检查、窗口中的分组与标签拖拽检查 |
| SFTP 文件/目录、隐藏/空目录、断点续传、冲突、链接 | 核心真实 SFTP 检查；窗口中的选择、批量、文件承诺拖拽、独立窗口、断开/取消 |
| ZMODEM、trzsz | 真实助手进程及 PTY 上传/下载、字节比对、速度、tmux 与拖拽路径 |
| tmux、复制、输入法、字体缩放、断线重连 | 窗口检查及真实 SSH/tmux；包含 less 回放、持续输出选区、R/r |
| 主题、颜色、透明度、字体、六个设置页、中英文 | 完整窗口检查，含反复切换语言、小窗口与滚动 |
| 密码/密钥管理、关联、删除确认、备份 | 核心加密/篡改/格式测试及双语凭据界面检查 |
| 历史开关、容量、压缩、清理、导出 | 核心历史策略与窗口检查 |
| Codex 读取、分页、监控、执行审批/续期/撤权 | 核心协议及窗口 MCP/私有 socket 检查、真实 SSH 独立执行通道 |
| Codex 登录衔接、MCP 路径与代理隔离 | PTY 登录模拟、真实 CLI 参数解析、HTTP/SOCKS5 合成 HTTPS 目标 |
| X11 转发 | `x11-check.py`：生产 SSH 参数、临时 sshd、真实 XQuartz 窗口及退出清理 |
| 发布/安装一致性 | `package-release.sh`、`create-dmg.sh`、`install-release.sh`：多形态窗口检查、签名、完整包比较 |

## 覆盖边界

这些是功能回归，不是 100% 行/分支覆盖率，也不是所有功能组合的穷举证明。测试通过不代表不存在缺陷。

- X11 窗口测试需要 XQuartz，使用本机 SSH 转发和 xmessage；不代表所有远端图形应用或 GPU 加速均已验证。
- Codex 代理测试不调用真实模型、不验证付费账号/额度或模型建议质量；登录衔接采用模拟服务，不替代实际账号登录。
- Finder 文件承诺和面板手势有程序化检查，真实 Finder 拖放、设备输入法、屏幕分享及长时间使用仍需人工验收。
- 本机环回网络不代表公网高延迟、丢包、各种远端 SSH/SFTP 实现或硬件密钥均已验证。
- Apple Silicon 本机通过不等于 Intel 和最低 macOS 版本实机通过；短时进程回收检查不等于长期内存无泄漏证明。

## 可维护性约束

保持协议/持久化在 `MyTermCore`，窗口和交互在 `MyTerm`；手势与会话排序/分组修改分离。提取有明确职责的模块，不为缩短文件盲目重构。计时器与子进程要有关闭路径，后台结果要核对当前连接身份，分页与递归要有上限。缺陷优先加入可复现检查，再验证修复。

`MyTermApp`、`CodexBridge` 仍承担较多界面编排职责，后续新增行为应优先放入专注模块；拆分时保留现有回归入口。第三方 SwiftTerm 修改应记录于 `vendor/SwiftTerm/MYTERM-PATCH.md`，不要直接改动上游许可证。
