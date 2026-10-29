# MyTerm development context and handoff

[简体中文](DEVELOPMENT-CONTEXT.md) · English · [User guide](../README.en.md) · [Workflow](../AGENTS.md)

This document distills the long-running development conversation into repository-owned decisions. It is neither a transcript nor a complete manual. It includes only MyTerm context, excluding credentials, private machine details, real session IDs, terminal output and unrelated remote failures. Code, tests and user documentation define current behavior; [CHANGELOG](../CHANGELOG.en.md) records historical releases. New requirements may revise these decisions. Old conversations are not permanent authorization.

## Starting a new session

Give a new Codex session or contributor this prompt:

> Read AGENTS.md, docs/DEVELOPMENT-CONTEXT.en.md and README.en.md first. For Codex integration, also read docs/CODEX-INTEGRATION.en.md and docs/PERMISSIONS.en.md. Inspect current Git state, version, recent commits and relevant implementation rather than assuming the handoff snapshot remains current. Identify behavior to preserve and unresolved verification, then complete the task I specify, update both documentation languages and run appropriate checks. Do not restore superseded designs or automatically publish, delete releases or interrupt ongoing work based on past requests.

Start with read-only checks; do not reset the workspace to inspect it:

```bash
git status --short --branch
git log -5 --oneline
plutil -p packaging/Info.plist
```

`packaging/Info.plist` is the version source; see the [testing guide](TESTING.en.md). This document stores no live sessions, model memory or credentials. Resuming development does not restore an SSH connection or a Codex execution grant.

## Product goals and scope

- A native macOS terminal workspace, originally seeking a MobaXterm-like SSH experience. SwiftUI/AppKit, SwiftTerm and system OpenSSH support local Bash, SSH, file transfers and Codex.
- Focus on macOS terminal quality. Windows and VNC were discussed but are not in the current implementation scope. General multi-AI integration was also deferred; Codex remains the supported integration.
- Address users first: DMG installation, dependencies, first-run permissions and usage belong at the front of README; source builds and tests belong at the end. Maintain Chinese and English together.
- Credit Junli Zhang with the public GitHub profile, without an email address. Repository: https://github.com/junli-nv/MyTerm.
- Prioritize maintainability: separate UI, state, protocols and process management instead of accumulating fixes in a large callback; test meaningful behavioral boundaries.

## Important designs and their evolution

### SSH, credentials and jump hosts

SSH supports password/key authentication, OpenSSH import/export, jump chains, independent HTTP/SOCKS5 proxies, forwarding, compression, keepalive and debugging. X11 defaults off. SSH setup can accept a password or leave it blank for a later prompt; password and key selection should be clear. Editing unrelated configuration must not discard valid credential associations. A replacement entered after password rejection should be reused on subsequent connections.

The app manages credentials rather than using the system Keychain as its default store. Passwords support names, reveal and session associations; keys show references and require extra confirmation before deleting a referenced key. Preference backups can contain secrets and must retain encryption and integrity checking. OpenSSH exports must not include passwords.

Jump hosts evolved into independently managed shared definitions with names, CRUD, references and route testing. Migrate existing configurations and reuse matching route/user credentials. Equal IP addresses alone do not justify merging distinct credentials, proxies or routes. Referenced jumps must be detached before deletion. Tests must accommodate Windows and forwarding-only hosts instead of treating unsupported Unix commands as SSH failures. OpenSSH export must distinguish repeated addresses, aliases and actual references.

The SSH editor no longer offers whole-route saved jump presets. Use Choose Existing Jump Host to append individual hops or Change Jump Host to replace one, with independent jump management retained. Selecting a hop does not replace other hops or the proxy; existing references and credentials remain intact.

### Tabs, layout, input and themes

- Start at the welcome page without automatically opening a shell. Double-click saved SSH servers to connect; a single tab selection must allow its context menu without another focus click.
- Drag tabs to reorder. Edit Tab combines name, color and environment label. Saved sessions have tree groups, drag-in/out and group creation by dropping one ungrouped session onto another.
- Preserve double-clicking empty tab-bar space to maximize/restore. Keep title space compact and the bottom bar hideable. Place SFTP access at the upper right to avoid layout movement between local and SSH tabs.
- Support configurable split shortcuts, default `⌘⇧H` / `⌘⇧V`. Split only the selected pane into equal halves, preserving other ratios; local/SSH splits create the same connection type by default. Broadcast only to explicitly selected panes.
- Selection-to-copy and right-click-to-paste are important habits. Preserve tmux/vim, Chinese input, key repeat, soft-wrap copying and selection during output. Avoid global interception that breaks full-screen input or mouse protocols.
- Font minimum is 5 pt; Ctrl+two-finger gestures and `⌘+`/`⌘-` adjust in small steps. Themes include palettes, ANSI colors and opacity. Custom font-name entry and font-search controls were removed; font selection remains.
- Settings and Codex integration use vertical navigation. Small windows scroll with confirmation/cancel accessible. Language switches immediately, including system-inserted menu items. Configuration windows follow the current desktop.

The main window remains transparent to support terminal opacity. The tab/terminal separator uses a single physical pixel and needs its own opaque backing; do not fix chrome seams by disabling transparency for the entire window.

Nested HSplitView hosts can reintroduce native titlebar safe-area insets below the custom strip. Overlay the line inside the strip, ignore the duplicated top safe area on the terminal surface, and disable the system titlebar separator. Regression checks must cover adjacent geometry, not just one opaque pixel row.

### File transfers

SFTP is the file-management entry point; the separate SCP UI was removed. Preserve disconnect, reliable selection, multi-selection, context-menu download, drag/drop, recursive directories, speed, resume and detached windows. Upper-right access must not depend on expanding the bottom bar.

Existing files need overwrite/skip and batch choices, not disconnected SFTP or silently suffixed `.0` files. Overwrite and resume are distinct; preserve interrupted-transfer recovery. ZMODEM conflict/staging/resume behavior differs from SFTP and must not claim equivalent source validation.

MyTerm bundles a trzsz client; the remote needs `trz`/`tsz`. ZMODEM requires local and remote `rz`/`sz`. Use trzsz for tmux and account for jump relays. Transfer detection must neither delay ordinary echo such as a lone `*` nor break protocol detection while reducing buffering.

Do not cap inline SFTP content width while painting only the content background: widening the split can expose transparent margins. Fill the allocated pane and ignore the duplicated top safe area. Test expansion beyond the former 520pt cap, contraction and intermediate layouts. Panel-only samples are insufficient: while terminal sizing is debounced, its document retains the old width. Intersect the background exclusion with the scroll clip viewport and repaint after sizing, or the right gutter becomes transparent and appears to change divider thickness. Retain the native 1pt divider and inspect the entire boundary before and after sizing.

### History, logs and resource lifecycle

Memory scrollback and disk logs are separate. Disk logging defaults off. Sessions can override global policy; support line/capacity limits, cleanup, export and compression. History search cannot recover evicted data.

Earlier investigation found delayed PTY release for retained exited screens, UUID cleanup gaps and substantial terminal-line memory use. Fixes addressed these areas and added an estimated global history budget: default 256 MiB, shared among terminal tabs; 0 uses line limits only. This is not a process-memory hard cap and excludes current screens, images and UI. A stable sample cannot establish zero long-term leaks.

Normally exiting local/SSH tabs follow exit-close behavior; network disconnects preserve output, show status and allow R/r reconnect. External Codex/IDE `MyTerm --myterm-mcp` processes are not necessarily abandoned GUI children. Inspect parents and pipes instead of killing every process with that name.

### Codex boundaries and authorization

See the detailed [integration contract](CODEX-INTEGRATION.en.md). These are the decisions most likely to be misread from old conversations:

| Earlier design | Later decision and current constraint |
| --- | --- |
| Read-only SSH integration | Execution is supported and selected by default in the chooser, effective upon startup confirmation; uncheck for read-only |
| Always require individual confirmation | Allow Once and session Always Allow are switchable; old prompts must not override the actual UI mode |
| Fixed 10 minutes / 30 commands | Duration and budget are configurable and renewable in the running tab; do not restore old constants |
| Fixed 4096 bytes / 60 seconds / 1 MiB | These remain initial defaults, but limits and default approval mode are configurable; multiline scripts are supported |
| MyTerm captures and confirms plans | Codex displays plans; MyTerm does not duplicate them, and command approval remains separate |
| Continuous SSH monitoring | Automatic background sampling was removed; task-directed multi-step execution and result retrieval remain |
| Read old output on connection | Default to subsequent tasks; reading existing output is optional at launch, not a history access boundary |
| Local Codex requires associated Bash | Start directly in a working directory with the Codex proxy, without Bash association or MyTerm MCP |
| Global sharing switch and copying session IDs | Selecting SSH establishes association and passes the ID automatically; no manual copying or redundant global revocation entry |
| One execution grant per SSH tab | Codex tabs own separate grants, quotas and reading progress; execution is serialized on the shared SSH channel |
| Force `--no-alt-screen` / take over Codex scrolling | Reverted; retain terminal-protocol routing rather than restoring obsolete display overrides |

Codex and SSH proxies are independent. Reuse login across tabs. Paths, proxies, login, external registration and SSH MCP health have separate status. MCP, macOS permissions and command approval are different layers.

Commands use an independent noninteractive channel over an authenticated SSH ControlMaster, not the interactive terminal's directory, temporary environment or tmux state. Read all output pages and validate completeness. Explain `incomplete` rather than silently ignoring it to reduce noise. `execute_command`/`command_status` default to compact results, with waiting to reduce empty polling; Codex controls its tool-call UI.

Organize conversations by user-selected clusters/projects, with a default project. Support names and resuming history against a new SSH UUID. Allow removing index entries and configuring storage for future projects, without confusing MyTerm's index with Codex history. Closing one Codex tab ends only its grant, preserving other tabs on the same SSH session.

## Diagnostics and unresolved issues

1. **Codex scrollback jumps remain a known issue.** Scrolling up during output can jump much further back. Forced scroll interception was reported to worsen it and was reverted. A later release does not prove resolution; capture buffer/mouse modes, scrolling and output timing.
2. **There is insufficient evidence that the small SwiftUI menu leaks are gone.** Earlier samples reported small leaks, distinct from large history allocations. Use isolated instances, repeated open/close cycles and sampling without disrupting user work.
3. **SSH MCP checking is not an end-to-end Codex check.** It launches MyTerm MCP and checks initialization/discovery, not Codex's Code Mode host. A user attributed one incident to a system-blocked Codex helper; not every handshake failure has that cause.
4. **Permissions cannot be permanently pre-granted in one step.** Codex helpers can prompt separately; test actual SSH integration after installation/upgrade. A failed Gatekeeper assessment alone is not a root cause. See [permissions](PERMISSIONS.en.md).
5. **Do not claim every environment is tested.** Real hosts, input methods, trackpads, third-party TUI changes and enterprise policy may require reproduction on the affected machine. Distinguish passed, untested, unreproduced and known failures.

Help → Terminal Diagnostics provides bounded, opt-in recording and readable Chinese/English summaries. Capture timing, stages, error categories and guidance without terminal text or credentials. Explanations use local rules, not a model. State missing evidence; normal EOF, a process name or one exit code alone is not a diagnosis.

## Code and verification map

| Area | Starting points |
| --- | --- |
| UI and interaction | `Sources/MyTerm/`; `TabBarDragArea.swift`, `StablePaneSplit.swift`, `WorkspaceSplits.swift` |
| SSH, jumps and export | `Sources/MyTermCore/`: `Server.swift`, `SharedSSHJumps.swift`, `SSHJumpProbe.swift`, `OpenSSHExport.swift` |
| SFTP | Core `SFTPClient.swift` / `SFTPDirectoryTransfer.swift`; UI `SFTPModel.swift` / `SFTPFileTable.swift` |
| Codex launch/association | `Sources/MyTerm/CodexLaunchActions.swift`, `CodexBridge.swift`; core `CodexConnection.swift` / `CodexThreadClient.swift` |
| MCP and execution | `Sources/MyTermCore/CodexMCP.swift`, `CodexExecution.swift`, `CodexCommandWait.swift` |
| Diagnostics | Core `CodexMCPHealthCheck.swift`, `CodexMCPDiagnosticLog.swift`, `CodexDiagnosticSummary.swift`; UI `TerminalDiagnostics.swift` |
| History/memory | Core `SessionHistory.swift` / `TerminalHistoryBudget.swift`; UI `HistoryMemoryBudget.swift` |
| Terminal patches | `vendor/SwiftTerm/MYTERM-PATCH.md` and source; update patch notes alongside changes |
| Automated verification | `Tests/MyTermCoreTests/`, `scripts/`, [testing guide](TESTING.en.md) |

## Development, installation and publishing

Follow [AGENTS.md](../AGENTS.md). Inspect the workspace first and preserve unrelated changes. Use Bash and the current machine's Python environment conventions; the original maintainer's personal paths are not requirements for other contributors.

Functional changes require code/documentation checks and validation of Debug, Release and an actual DMG copy. Run relevant regressions and report gaps. Check both languages, minimum window sizes, state transitions and initial loading. Development success does not establish installed-app correctness. Follow packaging/installation verification for app changes; documentation-only changes require no build or restart.

The original maintainer authorized installation after DMG checks but has also explicitly paused replacement during active work. Honor the latest instruction and do not extend that machine's authorization to someone else's. Commit, push, release and release deletion are separate operations; report what completed. Publish only when requested. Cleanup instructions changed over time, so a past “keep only latest” is not a permanent policy. Preserve source tags and historical changelogs; retain releases unless cleanup is explicitly requested.

After patch `.12`, increment the minor version. The project progressed through 1.x, 2.0, 3.0, 3.1, 3.2 (splits), 3.3 and 3.4. Use changelogs for historical detail rather than deriving release notes from this summary.

## Handoff snapshot (2026-10-28)

This is the local state at this handoff, not automatically updated GitHub status:

- Version source: 3.4, build 197; release-related commit `5746fd6` added readable bilingual diagnostics.
- Later documentation commits: `7f5ea57` (Codex-helper permissions) and `7ff42c2` (user-focused installation/dependencies). Before this handoff edit, local `main` was two commits ahead of cached `origin/main`; remote status was not checked online during this inspection.
- This task adds context documents and maintenance links without app behavior changes. Publishing or deleting releases was not requested for this handoff task.
- Old conversations do not automatically schedule Windows, VNC or multi-AI work. The next task comes from the next user request; unresolved issues above remain tracked.

## Ongoing maintenance

Update both languages when scope, core behavior, authorization, release workflow or known-issue status changes. Record evidence when resolving an issue rather than just deleting it. Keep transient investigation data in diagnostic reports, not here, and exclude logs and secrets. Date snapshot updates and recheck Git/version state; never silently present old snapshots as live status. README/topic guides cover usage, CHANGELOG covers version history, AGENTS covers operating rules, and this document preserves rationale and constraints easily lost across conversations.
