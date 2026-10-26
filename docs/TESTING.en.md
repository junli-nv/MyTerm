# Testing and maintenance

[简体中文](TESTING.md) · English · [README](../README.en.md)

Codex execution configuration regression checks cover command byte bounds, settings serialization and backup validation, nested JSON transport for larger requests, output paging beyond 1 MiB, incomplete reasons, approval modes and renewal isolation, plus bilingual control rows and scrolling configuration forms.

## Full regression entry point

Run from the repository root. Requires a macOS GUI session, Swift, system OpenSSH/SFTP, Codex CLI, tmux, lrzsz, and a separate Python environment with `scripts/requirements-password-test.txt` installed. Missing dependencies fail rather than silently skipping suites.

```bash
bash scripts/check.sh
bash scripts/build-app.sh debug /tmp/myterm-check/Debug/MyTerm.app
python3 scripts/check-all.py /tmp/myterm-check/Debug/MyTerm.app --configuration debug
```

`--password-python` selects the password-test virtual environment, defaulting to `.test-venv/bin/python`. `--logs` selects a log directory; otherwise a temporary directory is created. Individual logs and `summary.json` retain exit codes and timings. Stop at failures, fix them, then rerun affected checks. GUI suites run serially to avoid competing for focus; avoid interacting with test windows.

Release checks require matching core binaries and the intended app:

```bash
swift build --build-system native -c release --product MyTermChecks
bash scripts/build-app.sh release /tmp/myterm-check/Release/MyTerm.app
python3 scripts/check-all.py /tmp/myterm-check/Release/MyTerm.app --configuration release
```

After installing and starting XQuartz, add `--x11` to test real windows with forwarding disabled, untrusted and trusted, plus channel-exit cleanup. `summary.json` records whether it was requested. Alternatively run `python3 scripts/x11-check.py`, selecting the build with `MYTERM_TEST_CONFIGURATION`.

The app argument can also be `/Applications/MyTerm.app` or a copy from the DMG. This entry point does not build, install, publish or modify releases. `swift test` is not a substitute: core regressions use the `MyTermChecks` executable target.

Split regression covers nested top/bottom and left/right layouts, real terminal mouse focus, move/detach, closing and collapse, saved-layout restoration and shortcut persistence. Core checks cover layout collapse, invalid references and shortcut conflicts. Divider proportions are not persisted. Regression checks also verify initial equal halves, stable sibling bounds when nesting, and retained parent proportions after manual resizing, further splitting and child closure.

Broadcast regression uses isolated Bash PTYs and file results to verify execution in two targets, unselected isolation, readiness confirmation, input bounds, Codex/disconnected/stale-connection rejection and cleanup on tab/layout changes. Submitting terminal input is not treated as proof of remote success.

Update regression covers version comparison, architecture selection, download URL restrictions, SHA-256 and size checks, and fixture GitHub HTTP success, rate limits and errors. `scripts/update-installer-check.py` uses temporary signed apps to verify replacement, preservation on version/signature failures and rollback on launch failure; it does not modify the installed user app.

## Feature coverage map

| Feature | Checks and scope |
| --- | --- |
| Local shell, PTY, exit, sizing, Unicode | `MyTermChecks`, Debug smoke, window checks |
| SSH authentication, aliases, compression, jumps, HTTP/SOCKS5, L/R/D forwarding | `integration-check.py`: temporary loopback sshd, proxies, echo services and multi-hop combinations |
| Password save, reuse, rejection and rotation | `password-check.py`: real OpenSSH askpass and temporary encrypted database |
| Group tree, drag, session restore/import/export | Core archive/group checks and window group/tab-drag checks |
| SFTP files/directories, hidden/empty folders, resume, conflicts, links | Core real-SFTP checks including atomic/portable replacement; overwrite/skip/batch choices and connection preservation after conflict cancellation; UI selection, batches, file promises, detached window, disconnect/cancel |
| ZMODEM and trzsz | Real helpers and PTY upload/download, byte comparisons, rates, tmux and drag paths |
| tmux, copying, IME, font zoom, reconnect | Window checks and real SSH/tmux, including less replay, streaming selection and R/r |
| Themes, colors, opacity, fonts, seven vertical settings categories, the three-section Codex sidebar, Chinese/English | Complete window checks, repeated language changes, small windows and scrolling |
| Password/key management, references, deletion approval, backup | Core encryption/tampering/format tests and bilingual credential UI checks |
| History opt-in, limits, compression, cleanup, export, memory budget and metadata release | Core/history window checks; 200 metadata cleanup cycles, shared budgets, width changes and opt-out |
| PTY lifecycle | 100 retained exited objects, 2 MiB final output, EOF before exit, restart and HUP/TERM-ignoring child cleanup |
| Codex reads, pagination, retired monitor/plan compatibility, failed-start rollback, last-owner tab revocation, execution approval/renewal/revocation | Core protocol and window MCP/private socket checks; real SSH independent execution channel |
| Codex login continuation, MCP paths, proxy isolation | Simulated PTY login, real CLI argument parsing, HTTP/SOCKS5 synthetic HTTPS targets |
| X11 forwarding | `x11-check.py`: production SSH arguments, temporary sshd, real XQuartz windows and exit cleanup |
| Release/install consistency | `package-release.sh`, `create-dmg.sh`, `install-release.sh`: multiple app forms, window checks, signatures and complete bundle comparison |

## Focused regressions

Jump-credential regression checks cover saving from the editor, blank retention, shared-route reuse, rejection and replacement, legacy record/name migration, ambiguous-prompt isolation, copied multi-hop routes and password references.

Trackpad regression checks cover page-key encoding from actual scroll events, fast mode, accumulated gestures, throttling, reversal, ignored momentum, and normal-shell/mouse-wheel isolation.

Keyboard-repeat regression checks cover the app-scoped accent-menu policy, repeated h/j/k/l/a events with an ASCII input source in normal/alternate screens, and Chinese preedit/commit. The original input source is restored. Synthetic repeats do not replace a physical long-press test; OS long-press thresholds and repeat rates still require manual verification.

Tab-menu regression sends full press/release gestures through NSWindow: single selection followed by right-click or Control-click, padding/edge hit areas, persistence after release, close buttons and action targets. Native drag payload checks cover reordering and invalid payloads. Additional cases cover primary-typed events with secondary button numbers, duplicate suppression for one press, and keyboard focus after switching. Rename checks use the real menu and dialog to verify immediate title/width updates, repeated edits, cancellation, and names after switching/reordering. Context-click checks also cover automatic selection of inactive tabs. Physical trackpad input still needs manual confirmation.

Forwarding-editor checks cover removing a middle rule, preserving other rules, stale IDs, saving/reloading an empty list and adding a rule again.

Codex inline approval checks switch languages repeatedly in the same window and recognize English labels in rendered button snapshots. Core checks cover the default executable and custom-path serialization.

Codex regressions also cover two clients on one SSH transport: independent grants, quotas, approval and output pages, serialized execution, independent expiry, renewal and close cleanup. A real stdio adapter verifies that tool arguments cannot override its environment-provided association.

## Limits of coverage

These are feature regressions, not 100% line/branch coverage or exhaustive combinations. Passing tests does not establish that no defects remain.

- X11 window checks require XQuartz and use loopback SSH with xmessage; they do not validate all remote graphical applications or GPU acceleration.
- Codex proxy checks make no real model requests and do not validate paid accounts, quota or model diagnosis quality. Simulated login continuation does not replace a real account login.
- File promises and panel gestures have programmatic checks; actual Finder drag-and-drop, device IMEs, screen sharing and long-running usage still need manual acceptance.
- Loopback networking does not validate public-network latency/loss, every remote SSH/SFTP implementation or hardware key.
- Apple Silicon results do not validate Intel or the minimum supported macOS on real hardware. Short process-cleanup checks cannot prove the absence of long-term memory leaks.

## Maintainability rules

Keep protocol/persistence in `MyTermCore`, windows/interactions in `MyTerm`, and gestures separate from session/group mutations. Extract focused responsibilities, not arbitrary file fragments. Timers and child processes need shutdown paths; asynchronous results must check connection identity; pagination and recursion need bounds. Reproduce defects before checking fixes.

`MyTermApp` and `CodexBridge` still carry substantial UI orchestration. Prefer focused modules for new behavior and retain regression entry points during extraction. Record third-party SwiftTerm changes in `vendor/SwiftTerm/MYTERM-PATCH.md`; preserve upstream licenses.

Terminal diagnostics checks cover opt-in recording, 15-minute expiry, ring capacity, concurrent writes, clearing, and exported ZIP round trips. Terminal input checks cover output following after selection and resumed input, keyboard-protocol changes after composition ends, and the first ASCII Return press in normal/alternate buffers with multiple keyboard modes. Synthetic events do not replace physical-device or long-running real Codex interaction checks.

Codex launch-form checks expand all settings in Chinese and English at 640×480 and 800×700, verifying that Cancel and launch buttons remain fully visible outside the scroll view.

Resume regressions cover native history-picker arguments, binding a new SSH UUID, rejecting old UUIDs, and authorization/association cleanup. Control-bar checks cover full-width layout and scrolling in narrow windows. `scripts/codex-resume-check.py /path/to/MyTerm.app` uses the real Codex CLI with isolated configuration and a synthetic conversation to verify restored text and fresh MCP initialization, without reading private conversations or calling a model. Release packaging runs this check; it does not replace real-account or model-behavior testing.

Disconnected SSH status-bar checks resize through wide and narrow pane widths in both languages, verifying full-width content or horizontal scrolling.

OpenSSH export checks use system `ssh -G` to verify independent users/ports for sessions sharing a host, stable aliases, existing-host collisions and repeated inputs.

Shared-jump regressions cover exact legacy backups, definition deduplication, route/authentication isolation, propagated updates, independent copies, dangling references, conflict rejection, archives/reloads, and unchanged credential indexes. Editor checks verify password reveal/hide preserves draft text, starts masked, and never saves passwords in configuration JSON.

SSH inventory regressions cover deleted nodes still referenced as jumps, current/snapshot export scope, saved/missing/unknown credentials, explicit key-file availability, unreferenced passwords, asynchronous loading and bilingual small-window scrolling. Checks do not attempt real login or verify password correctness.

Jump-host regressions cover independent persistence, reference protection, propagated edits, deletion, bilingual minimum layout and archive compatibility. `scripts/jump-probe-check.py` uses temporary keys and isolated loopback sshd to verify direct/routed SSH, wrong keys and cancellation; it never connects to user servers.

`scripts/jump-password-probe-check.py` runs an isolated password-only SSH server that rejects all remote channels. It verifies saved-password reuse, wrong-password rejection, absence of shell/exec requests and connection cleanup. Release GUI checks run it using `.test-venv/bin/python` with `scripts/requirements-password-test.txt`; override with `MYTERM_PASSWORD_TEST_PYTHON`. This simulates restricted server capabilities, not validation on an actual Windows host.

- `scripts/codex-cluster-check.py .build/release/MyTermChecks`: real Codex create/name/rename/persistence, directory isolation and native UUID resume with isolated CODEX_HOME and a loopback mock provider; no model requests.

MCP diagnostic pipe regression: `python scripts/mcp-diagnostics-check.py /path/to/MyTerm.app` uses isolated temporary files to cover handshake, discovery, EOF, malformed input, size limits, closed output pipes and privacy boundaries without calling SSH tools. Packaging, DMG and installation checks all run it.

Diagnostic-summary regressions cover Chinese/English explanations, unchecked/no-event states, unknown reasons without raw-text echo, normal EOF, dropped events, failing helpers alongside a successful probe, and both readable files matching the original metadata in the actual ZIP.
