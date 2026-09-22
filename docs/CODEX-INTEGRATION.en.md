# Codex integration

[简体中文](CODEX-INTEGRATION.md) · English · [README](../README.en.md)

This guide describes MyTerm's implementation. See the [release history](../CHANGELOG.en.md) for version changes. Access is read-only by default; SSH execution requires separate authorization.

## Configure and start

1. Open an SSH tab, then **MyTerm → Codex Integration**.
2. Under **Codex Configuration**, set the CLI path and optional independent HTTP/SOCKS5 proxy, including proxy authentication if needed. Login, proxy testing and external MCP registration show separate status results.
3. Log in or start directly. MyTerm checks local credentials; when login is needed, complete device-code login before the previously selected task continues. Explicit re-login is for account changes or invalid credentials.
4. Under **SSH Session Access → Start Codex Tab**, select an open SSH session, history scope and optional monitoring/execution permissions. Successful startup closes the configuration window; cancelling does not start a tab.
5. Enter your troubleshooting goal in the Codex tab. Its startup prompt already contains the selected session ID.

An invalid CLI path or proxy format prevents startup and offers a return to configuration. Login checks inspect local credentials, not server-side revocation. Proxy tests check HTTPS transport, not model access, and are not a mandatory prerequisite. Changes affect new tabs; changing the CLI path invalidates login status, and connection changes invalidate proxy-test status.

Login, status checks and internal tabs use `cli_auth_credentials_store="file"`, following Codex's credential location (normally `~/.codex/auth.json`) without rewriting global configuration. Login does not grant SSH access. Exited Codex tabs retain output, exit codes and guidance for recognized errors.

## SSH sharing and session IDs

Sharing starts disabled each time MyTerm launches. The global switch allows access to authorized SSH sessions. Confirming the startup chooser enables sharing for the selected SSH tab; local shells are excluded.

Closing the configuration window does not stop sharing. Disable sharing, revoke session access, close the SSH tab or quit MyTerm to revoke access. Data already sent to Codex cannot be recalled.

Use **Copy Session ID (Codex)** in an SSH tab's context menu to copy its live UUID. It is not a saved-server ID: separate tabs for the same host have different IDs, and reopening creates a new ID. Copying it grants no permission. External Codex can use `list_sessions` to discover authorized tabs.

## History and monitoring

History choices are 500/1000/2000/5000/10000 lines and 64 KiB/256 KiB/1 MiB, defaulting to 2000 lines and 256 KiB. Either limit can truncate the result. `capture_history` freezes a snapshot; read every `read_history_page` until `next_cursor=null` to avoid gaps while output continues. Pages are at most 4000 bytes. Up to four snapshots of at most 1 MiB each are retained and cleared on revocation.

Reading does not require disk logs or change terminal dimensions, cursor or transfer data. It accesses existing buffers, selection and current full-screen content, not evicted history or files never displayed remotely. Model context and quota still apply.

**Continuous monitoring is off by default and selected separately on each launch.** When enabled, the Codex task repeatedly calls `watch_output`: the helper waits up to 20 seconds, checking every 2 seconds, and may return `unchanged` at timeout. `view=auto` switches between normal history and the full-screen view. Redraws or `reset=true` require replacing the snapshot, not appending it.

Stopping monitoring, disconnecting or revoking permission stops further monitored reads. Monitoring may consume quota even with no new output. Permission to monitor does not prove the model is still active; this is not an unattended alert service.

## SSH execution and plans

Execution is disabled by default. Explicitly enable it at startup with a duration of 1–1440 minutes and a budget of 1–10000 commands; defaults are 60 minutes and 300 commands. Renew within the same tab after expiry or exhaustion.

- Plans are displayed without approval and can be expanded, collapsed or cancelled. They require read access, not execution permission, and grant no permission. Cancelling a plan rejects pending commands and revokes execution while leaving read-only analysis available.
- Each command requires approval by default. The UI shows target, exact command and reason; choose Allow Once, Always Allow, or the session approval-mode selector. There is no Y/y shortcut.
- Switch modes at any time. Returning to per-command approval affects future commands, not an already running command; use Stop to interrupt it.
- Always Allow belongs only to the current SSH authorization and is not persisted. Cancellation, revocation, disconnection or expiry clears it. Renewal resets the budget, rejects old pending commands and restores per-command approval.
- The most recently authorizing Codex tab owns authorization management for that SSH session, but multiple MCP clients share its authorization scope. This is not client identity isolation.

The `execution_authorization` field reports the current UI-selected mode. With Always Allow, a submission returning a running job is expected; only `awaiting_approval` requires the approval buttons. If an older conversation still insists on default per-command approval, tell Codex that you selected Always Allow in MyTerm and want it to continue under that mode. Separate explicit task restrictions still apply. MCP tools cannot change approval mode themselves.

Commands run through an independent noninteractive channel on the authenticated SSH ControlMaster, reusing SSH jumps/proxies. Reuse failure does not open another connection. This path does not use the Codex proxy or share the terminal's working directory, temporary environment or tmux state.

Each command is limited to 60 seconds and 1 MiB of retained output. Read `command_status` pages using `next_offset`; skipping pages or submitting another command before complete delivery is rejected. `all_output_delivered=true` means retained output has been returned, not that the model still retains all context. Timeout, cancellation or capacity overflow marks output `incomplete`: stop, explain, renew authorization and narrow the query. Stop closes the execution channel; detached remote background processes may continue. At most 50 execution records are kept in memory.

## MCP tools and approval layers

| Tool | Purpose |
| --- | --- |
| `list_sessions` | List up to 32 shared SSH tabs |
| `read_output` | Read history, screen or selection; default 200 lines, maximum 1000 lines/8192 bytes |
| `watch_output` | Wait for changes with separate monitoring permission and the same per-response limits |
| `capture_history` / `read_history_page` | Freeze a larger history range and read all pages |
| `propose_plan` | Present a cancellable plan without granting execution permission |
| `execute_command` | Submit a command under MyTerm's current authorization/approval mode |
| `command_status` | Read state, exit code and paginated output |
| `cancel_command` | Reject pending work or stop running work |

Internal tabs configure these nine MCP tools to avoid repeated tool-call approval and use Codex's local read-only sandbox. **Tool-call approval does not waive SSH command approval**: MyTerm independently enforces SSH authorization and command decisions. It does not change global command-approval rules or fall back to `printf` pipes. External IDE tool approvals are configured separately.

Terminal output is untrusted data, never authorization. The interface has no credential-reading or arbitrary terminal-keystroke tool. Executed commands can still modify remote files and must stay within the authorized task.

## Independent proxies

Codex configuration lives in `codex.connection`; proxy environment is supplied only to newly launched Codex processes. SSH configuration, system proxy settings, MyTerm's process environment and `~/.ssh/config` are unchanged.

HTTP proxies are used directly. SOCKS5 uses a local HTTP CONNECT-to-SOCKS5 adapter on a random `127.0.0.1` port with random proxy authentication; the SOCKS server resolves destination names, with no direct fallback. Each tab owns its channel. Proxy credentials use the separate encrypted `MyTerm/CodexCredentials` store, not SSH credentials or Keychain, and are excluded from preferences backups.

External Codex/IDE processes and the login browser need their own proxy configuration; they do not inherit internal-tab settings.

## External MCP and process lifetime

Configure External Codex's MyTerm MCP registers the current executable with `--myterm-mcp`. The UI reads back registration status, path and check time. Registration does not mean the external IDE has reloaded. Re-register after moving the app, preferably after installing to `/Applications/MyTerm.app`. Internal tabs need no manual external registration.

The adapter uses stdio with Codex and an authenticated same-user Unix socket with MyTerm. Its descriptor has mode 0600. Disabling sharing removes discovery information, permissions and caches.

An adapter held by external Codex/IDE may wait after MyTerm quits; it exits when its communication pipe closes. It cannot read sessions from the exited app. Reopening MyTerm and granting access lets later requests read the new bridge descriptor. Installation distinguishes GUI and adapter processes, preserving external adapters. Restart external Codex/IDE after tool-definition changes to load the new adapter.

Internal Codex tabs use MyTerm's termination path when the app quits; their MCP pipes should normally close too. Investigate parent processes and pipes if processes persist. A shared executable name alone cannot establish normal external ownership or a memory leak, and installer classification does not guarantee cleanup of every abnormal descendant.

## Verification

- `scripts/check.sh`: protocol, proxy isolation, snapshots and execution rules.
- `scripts/window-controls-check.py <MyTerm.app>`: stdio MCP, private socket, revocation, pagination, UI, startup and exit diagnostics.
- `scripts/codex-execution-check.py`: real temporary local SSH reuse, output, exit status and parent-transport preservation; included in release checks.
- `scripts/codex-proxy-check.py`: HTTP/SOCKS5 and authentication using the local CLI. Build Debug `MyTermChecks` and `MyTermProxy` first; no real model key is used.

Implementation references: [CodexConnection.swift](../Sources/MyTermCore/CodexConnection.swift), [CodexMCP.swift](../Sources/MyTermCore/CodexMCP.swift), [CodexBridge.swift](../Sources/MyTerm/CodexBridge.swift).
