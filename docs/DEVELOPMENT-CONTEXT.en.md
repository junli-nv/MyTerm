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

Organize conversations by user-selected MyTerm cluster groups, with a default group. Support names and resuming history against a new SSH UUID. Allow removing index entries and configuring storage for future projects, without confusing MyTerm's index with Codex history. Closing one Codex tab ends only its grant, preserving other tabs on the same SSH session.

MyTerm manages these groups separately from native Codex projects. Refresh conversations checks only metadata for existing entries in the selected group and updates names. It does not request conversation turns or SSH output, run SSH commands or start model analysis. Status distinguishes unchecked, available to resume, not found and unable to verify. Unknown errors, permission failures and timeouts are not deletion evidence. The batch is limited to about 30 seconds; an ambiguous failure stops further queries and preserves all entries for retry. Results describe this check only and reset when reopening the chooser; resuming still validates the directory again. Refresh does not change the last-opened date.

Rename group changes only the display name, preserving its ID, directory, conversation IDs and SSH associations. A renamed default group remains the default entry. Existing tab titles stay unchanged; newly opened tabs use the new name. Deleting the default group recreates it on the next opening.

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

## 2026-10-31: forwarding and Codex scrolling

MyTerm forwarding rules now start after authentication via bounded ControlMaster requests. Session-only switches never edit saved rules. Duplicate specifications share one switch. Failure preserves SSH; enabled is listener acceptance, not target reachability. External SSH-config rules remain unmanaged. Reconnect resets switches. Late replies must not revive a stopped generation.

Built-in Codex tabs use standard application wheel routing, isolated from tmux/full-screen Fast and Page settings. Fractional motion resets across buffer/routing changes and new gestures. No forced `--no-alt-screen` or global configuration changes. Real user scroll jumps remain unconfirmed; protocol regressions alone do not prove resolution. Diagnostics now include optional mouse-reporting and built-in application-routing flags, without text.

## 2026-11-04: password copying

Password management supports copying without revealing, always reading current storage rather than the reveal cache. Feedback excludes secrets. Revealed passwords use a native selectable read-only field; list buttons act independently. Focus-loss hiding remains. Tests use synthetic credentials and an isolated pasteboard.

## 2026-11-15: first-click paste

Version 3.4.7 (build 206) opts terminal views into first-mouse delivery only for right-clicks without Shift when direct paste is enabled. A paste gesture from another app must perform the action on that first click; ordinary left-click and menu activation retain native policy. Window regressions inspect exact paste bytes, bracketed framing and focus in normal/alternate mouse modes. These checks do not establish physical VS Code switching or user-specific tmux behavior. Git at task entry was `ff809e2` (3.4.6); the dated October snapshot above remains historical.

## 2026-11-26: Codex transfers and interaction investigation

Entry Git was `acf8baa`, 3.4.7 (206); this local change uses 3.4.8 (207), without publishing authorization. Codex adds bidirectional file/directory SFTP tools, explicit per-transfer confirmation, progress/cancellation and validated resume. Reuse only the current ControlMaster, without fallback login. Authorization/budgets remain association-scoped; server-configuration identity permits download resume independently of transient socket paths. See the integration guide.

A stronger paste regression reproduced the old path leaving the keyboard window inactive; the handler now explicitly activates the app, window and terminal. Actual first-event delivery and device differences still require field validation. The user again reports Codex jumping to the top during streaming trackpad scrolling, unlike iTerm. Append/protocol regressions have not reproduced this; it remains unresolved. Diagnostics now capture gesture deltas/phases/momentum, before/after viewport, history rows/trimming and clear counts, without terminal text.

The user subsequently explicitly requested pushing the code and creating the 3.4.8 Release, using the validated local ZIP/DMG and SHA256SUMS while preserving historical releases. Release notes record the proxy end-to-end failure and unresolved streaming jumps; do not describe the full regression as entirely passing.

## 2026-11-27: transfer scope and Codex history replay

Entry was `7e8bd55`, 3.4.8 (207); the new local version is 3.4.9 (208). The user initially paused installation pending a save-and-confirm step, then explicitly authorized replacement once the build is complete. Current authorization is to finish package/DMG validation, then install, validate and reopen automatically without a second confirmation; preserve the old running app until validation finishes. The user subsequently explicitly requested pushing/publishing 3.4.9 and deleting only the preceding 3.4.8 Release and assets, while retaining its source tag, historical notes and all other Releases.

Transfer tools are only for explicitly requested Mac/SSH-host copies. Remote development edits/tests directly on authorized SSH; scripts, patches and here-documents are not local-file uploads. One shared scope feeds startup, MCP initialization and tool descriptions to avoid requiring source downloads.

Two user metadata captures confirm CSI 3J clears normal-buffer history and resets a scrolled reading viewport while mouse reporting is off. Built-in Codex now briefly retains a reading image and small content anchor, keeps parsing clears/replay, preserves wheel-row intent and restores after matching. An unmatched hold is bounded to two seconds before choosing the nearest available position. Input/terminal clicks and buffer switches release it. Images/anchors stay in memory, outside logs/exports; diagnostics add a holding flag. Never commit original diagnostics or real session details. Replay regressions do not replace physical trackpad acceptance; distinguish the confirmed mechanism from field validation.

## 2026-11-27: selection regression audit and release validation

Entry Git was `a96145c`, published 3.4.9 (208). The current local change is 3.4.10 (209). The user initially paused replacement while isolated Debug/Release/DMG copies were validated. After the complete results were reported, the user explicitly authorized installation, pushing the code, publishing 3.4.10, and deleting only the 3.4.9 Release/assets. Preserve the 3.4.9 source tag, historical notes and all other Releases. This authorization applies to this release operation, not future upgrades or publications.

The reported gap combines tmux copy-mode paging/scrolling with progressive double-click and clipboard output. Existing native-wrap selection and tmux/less copying checks covered the components separately. Retain the new synthetic real-tmux capture and old-fails/new-passes evidence. Coordinate redraws can leave missing or stale wrap metadata; explicit alternate-screen token/logical-row selection uses bounded visual continuation evidence without changing buffer flags. Exact-edge hard breaks remain ambiguous; keep screen-line copy. Blank-glyph delimiters include Braille blank and Hangul fillers, while emoji joiners stay part of tokens.

The audit also found mouse options, font/history persistence and group dialog/drop checks restricted to Debug smoke. They now run in the shared window suite, including Release and DMG. The full runner records pending/blocked suites and optionally continues independent checks after failures without hiding a failing exit. See the bilingual selection matrix for scope and manual boundaries; the results do not establish exhaustive platform or device combinations.

The expanded run found a harness deadlock when promoted NSItemProvider checks entered from a main-queue callback. The window-check launcher now uses a run-loop timer, allowing main-queue completions to run without weakening assertions. The proxy failure was reproduced with a PATH wrapper that overrides proxy environment variables; explicitly choosing the app-default CLI passed HTTP and SOCKS5 synthetic checks. Select the proxy-test CLI explicitly and retain its identity in the full summary; do not change user wrappers or rewrite historical failed results.

The remaining Debug-only app-smoke entry (welcome page, About panel and PTY/session smoke) is also promoted to Release. Packaging and actual-DMG verification run it alongside window checks; the full runner executes the same suite set in both configurations. Wide-character gaps in coordinate-painted rows and 22 rendered blank separators are now explicit cases; native trailing spaces remain intact.

One Release SSH/tmux run timed out waiting for the normal-exit callback after two reconnects. Six subsequent real integration runs with added process-state diagnostics passed. The cause remains unconfirmed; no PTY lifecycle fix is claimed. Preserve the failed run and report it even if the final suites pass. Installation was still paused at that checkpoint.

Final focused selection checks also cover row drag across repainted records, keeping hard boundaries and removing inferred redraw padding per logical row. Selection-only wrap overrides can reject stale flags without changing the buffer. Trust native explicit-LF provenance before visual inference, so pristine exact-width hard breaks remain separate. Programmatic ranges/select-all reset token/logical mode; screen-line copy and native trailing spaces remain intact.

Full packaging also exposed a tab-menu edge-check failure. The fixture now resolves the live view after switching tabs, scrolls the test point into its visible bounds, tracks end notifications only for the menu under test, and requires a matching close notification. Failure messages retain open/survival/end, focus and attachment state. Keep the earlier failed log rather than treating a rerun as an explanation. Core-check freshness is now guarded by Swift source timestamps; final core runs must be rebuilt for their configuration.

Pre-install validation snapshot: 3.4.10 (209) passed all ten full suites in Debug and Release, including X11, plus package/actual-DMG window and startup-smoke checks, signatures and bundle comparison. ZIP/DMG checksums were verified. The installed/running app and `dist/MyTerm.app` remain 3.4.9 (208) under the installation hold; no push or publication was performed. Earlier SSH exit-timeout evidence remains open, despite six focused repeat passes and final full-suite passes. This local result does not establish physical-device, Intel or minimum-macOS acceptance.

The authorized upgrade installed 3.4.10 (209) from the validated DMG, verified the installed bundle and `dist/MyTerm.app` against the release app, and reopened `/Applications/MyTerm.app`. Installed window/MCP checks passed; the additional installed startup-smoke check is retained with the release validation logs. The publication uses the same tested application binary; updating the bilingual release notes only regenerates and revalidates the DMG container.
