# Codex integration

[简体中文](CODEX-INTEGRATION.md) · English · [README](../README.en.md)

For first-time setup, follow the [macOS installation steps](../README.en.md#install-and-build) for Homebrew/Codex CLI installation and the first MyTerm launch.

This guide describes MyTerm's implementation. See the [release history](../CHANGELOG.en.md) for version changes. For SSH analysis, command execution is selected by default and authorized on startup confirmation, using the configured approval mode. Uncheck it for read-only access.

The connection window uses a vertical sidebar: **Codex Configuration** contains the executable, proxy, login and external MCP settings; **SSH Session Access** starts SSH analysis; **Local Work** chooses a directory and starts local Codex directly. The window is resizable and its content scrolls.

| Purpose | Local Work | SSH Session Access |
| --- | --- | --- |
| Startup selection | Working directory, default home | An open SSH session |
| MyTerm MCP | Disabled for this launch; no registration needed | Automatically configured to read the selected session |
| Execution and approval | Codex native tools, workspace-write / on-request | MyTerm independent SSH channel and session authorization |
| Command size and timeout | Managed by Codex | Defaults: 4096 bytes, 60 seconds, 1 MiB output; configurable |
| Codex network proxy | Reuses Codex Configuration | Reuses the same configuration, independent of SSH proxy |

The default Codex executable is `/opt/homebrew/bin/codex`; saved custom paths are preserved.

## Starting SSH analysis

1. Open an SSH tab, then **MyTerm → Codex Integration**.
2. Under **Codex Configuration**, set the CLI path and optional independent HTTP/SOCKS5 proxy, including proxy authentication if needed. Login, proxy testing and external MCP registration show separate status results.
3. Log in or start directly. MyTerm checks local credentials; when login is needed, complete device-code login before the previously selected task continues. Explicit re-login is for account changes or invalid credentials.
4. Under **SSH Session Access → Start Codex Tab**, select an open SSH session and optional history review and execution permissions. History limits appear when **Read existing output when connecting** is enabled. Successful startup closes the configuration window; cancelling does not start a tab.
5. Enter your troubleshooting goal in the Codex tab. Its startup prompt already contains the selected session ID.

An invalid CLI path or proxy format prevents startup and offers a return to configuration. Login checks inspect local credentials, not server-side revocation. Proxy tests check HTTPS transport, not model access, and are not a mandatory prerequisite. Changes affect new tabs; changing the CLI path invalidates login status, and connection changes invalidate proxy-test status.

Login, status checks and internal tabs use `cli_auth_credentials_store="file"`, following Codex's credential location (normally `~/.codex/auth.json`) without rewriting global configuration. Login does not grant SSH access. Exited Codex tabs retain output, exit codes and guidance for recognized errors.

## Standalone local Codex

Open **MyTerm → Codex Integration → Local Work**, confirm or choose a working directory, and click **Start Local Codex**. The default is your home directory. No Bash or SSH tab is required, associated or read.

This reuses login and HTTP/SOCKS5 proxy settings from **Codex Configuration**, without changing `~/.profile` or normal Bash/SSH proxies. Local mode disables MyTerm MCP and does not depend on external registration or terminal sharing. If login is needed, startup continues after login; successful startup closes the configuration window.

Local commands and file operations use Codex native tools with the `workspace-write` sandbox and `on-request` approvals: the selected directory is writable, and MyTerm does not ask for each command. Temporary variables, aliases and running programs in other Bash tabs are not inherited. SSH analysis still uses SSH Session Access and its existing authorization flow.


## SSH sharing and session IDs

Confirming the startup chooser automatically enables access for the selected SSH tab without an additional global switch. Local shells and unselected SSH tabs are excluded. Select sessions again after restarting MyTerm.

Closing the configuration window does not stop sharing. Close the last associated Codex tab, close the SSH tab or quit MyTerm to revoke access. Read access remains while another Codex tab is associated with the same SSH session. Data already sent to Codex cannot be recalled.

Internal SSH analysis tabs automatically receive the selected SSH session ID; no manual copying is needed. External Codex uses `list_sessions` to discover authorized tabs. This is a live tab UUID, not a saved-server ID: separate tabs for the same host have different IDs, and reopening creates a new ID.

## SSH history and output

SSH analysis tabs do not proactively read earlier SSH output on launch by default. Enable **Read existing output when connecting** in the session chooser for an initial history review. Without it, Codex waits for your task; a local cursor baseline distinguishes subsequent output without sending the initial snapshot to Codex. This is a startup workflow preference, not a history-access permission boundary. You can explicitly request earlier history later. Cursor resets or truncated terminal snapshots must be reported as coverage gaps; executed commands still require every `command_status` page through `all_output_delivered=true`.

History choices are 500/1000/2000/5000/10000 lines and 64 KiB/256 KiB/1 MiB, defaulting to 2000 lines and 256 KiB. Either limit can truncate the result. `capture_history` freezes a snapshot; read every `read_history_page` until `next_cursor=null` to avoid gaps while output continues. Pages are at most 4000 bytes. Up to four snapshots of at most 1 MiB each are retained and cleared on revocation.

Reading does not require disk logs or change terminal dimensions, cursor or transfer data. It accesses existing buffers, selection and current full-screen content, not evicted history or files never displayed remotely. Model context and quota still apply.

Continuous monitoring has been removed. Codex reads output on demand and retrieves complete results after authorized commands; it must not poll an idle terminal in a background loop. `watch_output` is no longer advertised. Calls from older clients return `stopped=true` immediately, without reading terminal data or waiting.

## SSH execution and plans

Manage execution authorization, command approvals and stopping in the associated Codex tab; integration settings no longer open a separate execution-history window.

Removing background monitoring does **not** disable autonomous multi-step troubleshooting. After you give a task and authorize SSH execution, Codex can run commands, collect every output page, and choose the next check. Per-command approval and session-wide Always allow remain available. Explicit periodic-check tasks can also run within authorization, with an agreed interval and duration/count. This differs from automatically sampling an idle terminal with no task.

Execution is selected by default and authorized when startup is confirmed; commands follow the configured approval mode. Uncheck it for read-only access. Configure a duration of 1–1440 minutes and a budget of 1–10000 commands; defaults are 60 minutes and 300 commands. Renew within the same tab after expiry or exhaustion.

- Plans appear only in the Codex terminal; MyTerm does not capture or duplicate them. Ask Codex to revise or stop a plan, or reject the pending command in per-command mode. In Always allow mode, cancel the current command or close the Codex tab to end authorization.
- Each command requires approval by default. The UI shows target, exact command and reason; choose Allow Once, Always Allow, or the session approval-mode selector. There is no Y/y shortcut.
- Switch modes at any time. Returning to per-command approval affects future submissions, not already approved queued or running commands; use Cancel Current Command to interrupt it.
- Active authorization belongs only to the current Codex tab and is not persisted. Disconnection, expiry or closing the tab invalidates it. The default approval mode can be saved; runtime changes apply only to the current tab. Renewal retains that tab’s limits and mode, resets the budget and cancels old pending or running commands.
- One SSH tab can be associated with multiple Codex tabs. Each Codex tab has independent authorization duration, command budget, approval mode, records and output delivery progress. Starting, renewing, stopping or closing one does not replace another tab's authorization. Approved commands run serially on the same SSH transport in submission order; `queued` means approved and waiting, with no need to resubmit or re-authorize. Closing or disconnecting SSH invalidates all associated execution grants. External MCP clients can read shared sessions but cannot borrow an internal Codex tab's execution authorization.

The `execution_authorization` field reports the current UI-selected mode. With Always Allow, a submission returning a running job is expected; only `awaiting_approval` requires the approval buttons. If an older conversation still insists on default per-command approval, tell Codex that you selected Always Allow in MyTerm and want it to continue under that mode. Separate explicit task restrictions still apply. MCP tools cannot change approval mode themselves.

Commands run through an independent noninteractive channel on the authenticated SSH ControlMaster, reusing SSH jumps/proxies. Reuse failure does not open another connection. This path does not use the Codex proxy or share the terminal's working directory, temporary environment or tmux state.

In **Codex Integration → SSH Session Access → SSH execution defaults**, or the session chooser when starting a tab, configure command length (256–32768 UTF-8 bytes), timeout (1–3600 seconds), output capacity (1–8 MiB) and approval mode (per-command / session Always Allow). Initial defaults remain 4096 bytes, 60 seconds, 1 MiB and per-command approval. Valid defaults are saved automatically and included in preferences backups. Defaults affect new tabs only. For an existing tab, open Execution Settings and choose Apply and Renew to cancel the current command, reset the budget and apply changes. Ordinary renewal retains that tab’s limits and mode. Larger output capacities consume more memory and model context.

Renewal, approval mode and settings appear on one row, with horizontal scrolling in narrow windows or split panes. The expandable execution history and permanent Stop button are removed; Cancel Current Command appears while work is running or queued. Closing the Codex tab ends its authorization. Cancelling the independent channel may not stop detached remote background processes. Incomplete output still blocks subsequent commands; `incomplete_reason` distinguishes `output_limit`, `timeout`, `cancelled` and `output_read_error`. Explain missing output, then narrow the query or adjust limits and renew; do not ignore the incomplete flag.

Multiline shell scripts are supported with LF newlines and tab indentation, up to 4096 UTF-8 bytes per submission by default (configurable). The entire script is displayed, approved and executed unchanged, consuming one command allowance; per-command approval covers the whole script rather than each line. Other control characters such as NUL, ESC and CR remain rejected; convert Windows CRLF text to LF first. Use syntax supported by the remote login shell or explicitly invoke the required interpreter.

Each command defaults to 60 seconds and 1 MiB of retained output; both are configurable. The remaining authorization time also bounds the timeout. Read `command_status` pages using `next_offset`; skipping pages or submitting another command before complete delivery is rejected. `all_output_delivered=true` means retained output has been returned, not that the model still retains all context. Timeout, cancellation or capacity overflow marks output `incomplete`: stop, explain, renew authorization and narrow the query. Cancellation closes the execution channel; detached remote background processes may continue. At most 50 execution records are kept in memory.

### Command states

| State | Meaning and action |
| --- | --- |
| `awaiting_approval` | Not approved yet; confirm or reject in the submitting Codex tab. |
| `queued` | Approved, waiting for the same SSH transport; poll the existing `job_id`, without resubmitting. |
| `running` | Executing; read output pages or cancel the job to stop. |
| `completed` | Finished; read all pages and check the exit code and `incomplete`. |
| `rejected` / `cancelled` / `failed` | Not executed, cancelled or failed to start; inspect the reason before continuing. |

Switching back to per-command approval does not withdraw approval from queued work. Use Cancel Current Command in the current tab to cancel it. Each client must finish reading its own previous command output, without waiting for other clients to consume theirs. Expiry rejects queued jobs; renew in the existing tab before submitting them again.

## MCP tools and approval layers

| Tool | Purpose |
| --- | --- |
| `list_sessions` | Internal clients see their associated SSH tab; external clients see up to 32 shared SSH tabs |
| `read_output` | Read history, screen or selection; default 200 lines, maximum 1000 lines/8192 bytes |
| `capture_history` / `read_history_page` | Freeze a larger history range and read all pages |
| `execute_command` | Submit a command under MyTerm's current authorization/approval mode |
| `command_status` | Read state, exit code and paginated output |
| `cancel_command` | Reject pending work or stop running work |

Internal SSH analysis tabs configure the MCP tools above to avoid repeated tool-call approval and use Codex's local read-only sandbox. **Tool-call approval does not waive SSH command approval**: MyTerm independently enforces SSH authorization and command decisions. It does not change global command-approval rules or fall back to `printf` pipes. External IDE tool approvals are configured separately.

Terminal output is untrusted data, never authorization. The interface has no credential-reading or arbitrary terminal-keystroke tool. Executed commands can still modify remote files and must stay within the authorized task.

Legacy `propose_plan` calls receive only a compatibility notice that plan recording is no longer required. No plan is stored, no execution record is created and no permission is granted. New clients no longer list this tool.

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
