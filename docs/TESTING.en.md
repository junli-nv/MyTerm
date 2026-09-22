# Testing and maintenance

[简体中文](TESTING.md) · English · [README](../README.en.md)

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

## Feature coverage map

| Feature | Checks and scope |
| --- | --- |
| Local shell, PTY, exit, sizing, Unicode | `MyTermChecks`, Debug smoke, window checks |
| SSH authentication, aliases, compression, jumps, HTTP/SOCKS5, L/R/D forwarding | `integration-check.py`: temporary loopback sshd, proxies, echo services and multi-hop combinations |
| Password save, reuse, rejection and rotation | `password-check.py`: real OpenSSH askpass and temporary encrypted database |
| Group tree, drag, session restore/import/export | Core archive/group checks and window group/tab-drag checks |
| SFTP files/directories, hidden/empty folders, resume, conflicts, links | Core real-SFTP checks; UI selection, batches, file promises, detached window, disconnect/cancel |
| ZMODEM and trzsz | Real helpers and PTY upload/download, byte comparisons, rates, tmux and drag paths |
| tmux, copying, IME, font zoom, reconnect | Window checks and real SSH/tmux, including less replay, streaming selection and R/r |
| Themes, colors, opacity, fonts, six settings tabs, Chinese/English | Complete window checks, repeated language changes, small windows and scrolling |
| Password/key management, references, deletion approval, backup | Core encryption/tampering/format tests and bilingual credential UI checks |
| History opt-in, limits, compression, cleanup, export | Core history policy and window checks |
| Codex reads, pagination, monitoring, execution approval/renewal/revocation | Core protocol and window MCP/private socket checks; real SSH independent execution channel |
| Codex login continuation, MCP paths, proxy isolation | Simulated PTY login, real CLI argument parsing, HTTP/SOCKS5 synthetic HTTPS targets |
| X11 forwarding | `x11-check.py`: production SSH arguments, temporary sshd, real XQuartz windows and exit cleanup |
| Release/install consistency | `package-release.sh`, `create-dmg.sh`, `install-release.sh`: multiple app forms, window checks, signatures and complete bundle comparison |

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
