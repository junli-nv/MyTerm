# Project workflow / 项目工作规范

This file contains matching English and Chinese instructions. Both describe the same workflow; update them together.
本文中英文说明为同一套规范，修改时必须同步。

## English

### Environment and maintainability

- Use `/bin/bash` for shell commands; the user's startup configuration is `~/.profile`. Do not configure zsh.
- Prefer `/Users/junliz/.venvs/codex-py314/bin/python` and its `-m pip` for local Python work. Respect project-specific virtual environments; do not install packages into Apple-managed Python or Homebrew's base interpreter.
- Keep gesture handling separate from session mutations. Use descriptive names, small focused files and meaningful regression checks. Document behavioral invariants rather than restating code.
- Preserve user settings, credentials, saved sessions and unrelated work during changes and upgrades.

### Build, package and install

- For broad regression reviews and major releases, use `scripts/check-all.py` with explicit app and build configuration; retain suite logs and report unverified environments. See `docs/TESTING.md` and `docs/TESTING.en.md`.
- Installed and development apps must behave consistently. A successful development build alone is not release validation.
- After functional app changes, update the local installer. Run `scripts/package-release.sh` and `scripts/create-dmg.sh`; they validate Debug, Release and an app copied from the actual DMG, including bundle-content comparison.
- Once DMG checks pass, automatically install, validate and reopen without asking again; quitting sessions for this upgrade is authorized.
- Use `scripts/install-release.sh`: quit the GUI, copy the validated DMG app to `/Applications/MyTerm.app`, verify with `scripts/verify-app-copy.py` and `scripts/window-controls-check.py`, then open that exact installed path. Do not rebuild or substitute `dist/MyTerm.app` during installation.
- Keep `dist/MyTerm.app` identical to the validated installed/release bundle. Confirm the running executable path and version. Keep only the current local release package after successful validation and installation.
- Distinguish external `MyTerm --myterm-mcp` adapters from the GUI. Do not kill external Codex/IDE adapters just because they share the executable name; investigate parent processes and pipes when diagnosing leftovers.

### UI verification

- For settings/localization changes, test the entire settings window: repeatedly switch Chinese/English, retain the selected page, and click all six visible tabs. Keep explicit tabs; do not reintroduce an adaptive overflow menu.
- Configuration forms must scroll at their minimum window size, with long labels wrapping. Keep the SSH editor resizable, with maximize/restore and a visible vertical scrollbar. Check expanded jump, proxy and forwarding sections in Chinese/English in Debug, Release and the installed app.
- For asynchronous session state, test the initial/loading state as well as the settled state. Keep SFTP controls accessible without the bottom status bar and preserve tab-strip geometry when switching SSH/local tabs.

### Publishing and documentation

- When publishing is requested, publish and verify the new release before deleting older releases. Keep only the latest GitHub Release and its assets; preserve source tags and historical changelogs. Do not infer publishing authorization from an ordinary code or documentation edit.
- Maintain Chinese and English versions of current documentation together, with working language links. README is a usage guide, not a running list of version announcements. Use `releases/latest` for downloads and `packaging/Info.plist` as the version source.
- Check documentation against code, UI labels and scripts. Remove obsolete defaults, personal absolute paths from public examples, environment-specific test claims and duplicated contradictory sections.
- Historical changelogs and release notes describe their named versions: preserve those facts and mark them as historical. Do not rewrite past behavior to match the current app. Keep third-party licenses and upstream documentation intact.
- For documentation-only changes, check facts, language parity and relative links; rebuilding/reinstalling the app is unnecessary unless code, resources or packaging behavior also changed.

## 简体中文

### 环境与可维护性

- Shell 使用 `/bin/bash`，用户启动配置为 `~/.profile`，不要配置 zsh。
- 本地 Python 优先使用 `/Users/junliz/.venvs/codex-py314/bin/python` 及其 `-m pip`。尊重项目虚拟环境，不向 Apple 管理的 Python 或 Homebrew 基础解释器安装包。
- 手势处理与会话数据修改分离，使用清楚的命名、小而专注的文件和有意义的回归检查；注释说明行为约束，不重复代码。
- 修改与升级保留用户设置、凭据、保存会话及无关工作。

### 构建、打包与安装

- 全面回归审查与大版本发布使用 `scripts/check-all.py`，显式指定应用及构建配置；保留测试日志并说明未验证环境，详见 `docs/TESTING.md` 与 `docs/TESTING.en.md`。
- 安装版和开发版必须行为一致，开发构建成功不能替代发布验证。
- 完成功能修改后更新本地安装包。运行 `scripts/package-release.sh` 和 `scripts/create-dmg.sh`，验证 Debug、Release 和从实际 DMG 复制的应用，并比较包内容。
- DMG 检查通过后自动安装、验证并重新打开，不再确认；用户已授权升级时关闭会话。
- 使用 `scripts/install-release.sh`：退出 GUI，从验证后的 DMG 复制到 `/Applications/MyTerm.app`，用 `scripts/verify-app-copy.py`、`scripts/window-controls-check.py` 检查，再打开该安装路径。安装时不得重建或用 `dist/MyTerm.app` 替代 DMG 产物。
- `dist/MyTerm.app` 与验证后的安装/发布包保持一致，确认运行路径和版本；验证安装成功后，本地只保留当前发布包。
- 区分外部 `MyTerm --myterm-mcp` 适配器和 GUI，不因可执行文件同名而结束外部 Codex/IDE 适配器；排查残留时核对父进程和通信管道。

### 界面验证

- 设置或本地化修改须验证整个设置窗口：反复切换中英文，保持当前页面，点击全部六个可见标签。保持固定标签，不引入自适应溢出菜单。
- 配置表单在最小尺寸可滚动，长文字换行。SSH 编辑器保持可缩放、可最大化/还原，并显示垂直滚动栏；在 Debug、Release 和安装版验证中英文展开的跳板、代理及端口转发区域。
- 涉及异步会话状态时，验证初始/加载状态与完成状态。SFTP 入口不得依赖底栏，切换 SSH/本地标签保持标签栏布局稳定。

### 发布与文档

- 用户要求发布时，先发布并验证新版本，再清理旧 Release。GitHub 仅保留最新 Release 及附件，保留源码标签和历史日志；普通代码或文档修改不自动授权发布。
- 当前文档的中英文同步维护，并提供有效语言链接。README 描述用法，不堆叠版本公告；下载指向 `releases/latest`，版本以 `packaging/Info.plist` 为准。
- 对照代码、界面文案与脚本核实文档；移除过时默认值、公共示例中的个人绝对路径、特定环境的临时测试结论和重复矛盾段落。
- CHANGELOG 和发布说明描述对应版本，保留历史事实并标明历史性质，不用当前行为覆盖旧记录。第三方许可证与上游文档保持原文。
- 纯文档修改检查事实、中英文一致性和相对链接；未涉及代码、资源或打包行为时，无需重新构建和安装应用。
