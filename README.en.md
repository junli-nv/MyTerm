# MyTerm

[简体中文](README.md) · English

Author: Junli Zhang · [GitHub](https://github.com/junli-nv)

[Repository](https://github.com/junli-nv/MyTerm) · [Download](https://github.com/junli-nv/MyTerm/releases/latest) · [Release history](CHANGELOG.en.md)

A native macOS SSH workspace built with SwiftUI/AppKit, SwiftTerm and system OpenSSH. It supports local Bash, SSH tabs, session groups, file transfers, standalone local Codex and Codex integration authorized per SSH session.

<a id="install-and-build"></a>

## Install and first use

Download the DMG for your architecture from the [latest release](https://github.com/junli-nv/MyTerm/releases/latest), open it and drag MyTerm into Applications. The release page and `SHA256SUMS.txt` provide the version, build and checksums. Packages are ad-hoc signed, without Developer ID signing or Apple notarization. Normally, install the DMG directly; building from source is unnecessary.

### Install MyTerm from scratch

MyTerm requires macOS 14 or later. Check About This Mac first: use an `arm64` package on Apple Silicon (M-series). Intel Macs need a matching package or a source build and cannot run the arm64 package directly. Available architectures are listed in the release assets.

| Feature | Local prerequisites |
| --- | --- |
| Local Bash, SSH, SFTP | MyTerm installer; macOS supplies Bash/OpenSSH/SFTP. Homebrew and Codex are not prerequisites |
| Codex local work or SSH analysis | Install Codex CLI first; the instructions below use Homebrew, so install Homebrew first |
| ZMODEM | Local and remote `sz` / `rz` (`brew install lrzsz` locally); see the transfer section |
| trzsz / tmux transfers | Client bundled with MyTerm; install `trz` / `tsz` remotely; see the transfer section |
| X11 forwarding | Install and run XQuartz; see the X11 section below |

1. Download the DMG and `SHA256SUMS.txt` from the [latest release](https://github.com/junli-nv/MyTerm/releases/latest), avoiding unknown repackaged copies.
2. In macOS Terminal, change to the download directory and run `shasum -a 256 <downloaded-DMG-path>` (replace the placeholder with the actual path). Compare the result with the matching checksum entry.
3. Open the DMG and drag MyTerm into Applications. Eject the DMG and launch MyTerm from Applications.
4. The welcome page lets you create a local Bash or SSH session. Codex is not required to start MyTerm.

### If macOS blocks the first launch

Packages are ad-hoc signed, without Developer ID signing or Apple notarization. macOS may report an unidentified developer or that it cannot check the app for malicious software. After verifying the source and checksum, try opening it once, then go to **System Settings → Privacy & Security → Security → Open Anyway**. Confirm Open and authenticate if requested. Future launches can use Applications. See [Apple's official instructions](https://support.apple.com/en-us/102445).

If Open Anyway is missing, try launching the app again; managed Macs may require administrator approval. For a damaged-app or will-damage-your-computer warning, verify the checksum and download again; report the exact warning if unresolved. Do not disable Gatekeeper system-wide.

### Optional dependencies: Homebrew, file transfers and Codex

Basic SSH, local Bash and SFTP work without these extra tools. Install only what you need below; MyTerm does not install these dependencies automatically. If Homebrew is already installed, check `brew --version` and skip its installation.

#### 1. Install Homebrew (package manager)

Run the command from the [official Homebrew instructions](https://brew.sh/) in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the installer and its **Next steps**. Homebrew's supported macOS versions can be newer than MyTerm's minimum; check [Homebrew requirements](https://docs.brew.sh/Installation) on older systems. Install Command Line Tools if prompted. Apple Silicon defaults to `/opt/homebrew`; load its environment in the current terminal:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
brew --version
```

Follow Next steps for your actual shell so new terminals also find `brew`; Bash examples use `~/.profile`. Do not use the Apple Silicon path for Intel or custom installations.

#### 2. Install file-transfer tools (optional)

**ZMODEM (`rz` / `sz`):** install [lrzsz](https://formulae.brew.sh/formula/lrzsz) on your Mac:

```bash
brew install lrzsz
command -v rz
command -v sz
```

The remote machine also needs lrzsz. On Debian/Ubuntu, for example, run `sudo apt install lrzsz` **in the remote SSH session**; use the appropriate package manager on other systems. Installing it on your Mac does not install it remotely. SFTP does not require lrzsz.

**trzsz (`trz` / `tsz`, for tmux and directory transfers):** MyTerm already bundles the client, so your Mac needs no additional client installation for MyTerm SSH transfers. Install the remote commands using the [trzsz-go installation guide](https://trzsz.github.io/go.html). For a remote Mac or Linux host with Homebrew, run:

```bash
brew install trzsz-go
command -v trz
command -v tsz
```

Run these commands on the machine that will execute `trz` / `tsz`. On hosts without Homebrew, use the upstream binaries for that operating system and architecture. If you also need these commands in your Mac's local shell, the same Homebrew command applies. The [trzsz-go package](https://formulae.brew.sh/formula/trzsz-go) also supplies the `trzsz` relay command for manually connecting onward from a jump host's tmux. Homebrew's `trzsz` and `trzsz-go` packages conflict; choose one, not both. See the transfer section below for usage and resume behavior.

#### 3. Install Codex CLI (optional)

Install the [Homebrew Codex CLI package](https://formulae.brew.sh/cask/codex) and check its path:

```bash
brew install --cask codex
command -v codex
codex --version
```

Update an existing Homebrew Codex installation with `brew upgrade --cask codex`. See the [official OpenAI documentation](https://learn.chatgpt.com/docs/codex/cli) for CLI usage and authentication.

### First Codex use: login, proxy and helper permissions

Open **MyTerm → Codex Integration… → Codex Configuration** and enter the full path returned by `command -v codex`. The default is `/opt/homebrew/bin/codex`; Intel Homebrew commonly uses `/usr/local/bin/codex`. Other installation methods may differ. Saved custom paths are not overwritten by the default.

If a proxy is needed, configure and test the independent HTTP/SOCKS5 proxy here before signing in and checking login status. It does not change the SSH proxy. This proxy applies to Codex started by MyTerm, not earlier Homebrew/CLI downloads; ensure Terminal can reach download sites during installation. Once signed in, choose Local Work or open an SSH connection and start analysis from SSH Session Access. See the [Codex integration guide](docs/CODEX-INTEGRATION.en.md).

After installing or updating Codex, complete the [helper-permission and SSH integration check](docs/PERMISSIONS.en.md#codex-helper-permissions). Codex helpers (such as `codex-code-mode-host`) may trigger separate macOS prompts; successful login or a passing MyTerm MCP check does not establish that these programs can run. The guide explains how to trigger the check early, handle the specific prompt and retest. MyTerm does not automatically grant system permissions.

Before using SSH analysis for real work:

1. Start a test SSH-analysis Codex tab with command execution and existing-output reading unchecked. Ask it only to discover MyTerm tools and confirm the SSH association.
2. If macOS blocks a named helper, verify its source and follow the matching system prompt. For an unidentified-developer warning, use Privacy & Security → Open Anyway as described above; other permission categories require their own handling.
3. Close the failed Codex tab and start a new one to retest. A successful login alone is not sufficient. If it still fails, follow the linked guide to record the prompt and export diagnostics.

### Check for updates

Use **MyTerm → Check for Updates…** to query the latest stable GitHub release manually. The window shows your version, the new version and release notes. After you choose Download and Install and confirm, MyTerm downloads the ZIP for your architecture, verifies SHA-256, application identity, version, architecture and code signature, then ends current terminal sessions, replaces the app and restarts it. Save ongoing remote and local work first. Settings and saved session configurations are retained; running processes are not restored. Installation failures retain or restore the previous app. Diagnostics are written to `~/Library/Logs/MyTerm/Update.log`.

Checks are manual, with no automatic polling. They use macOS networking settings independently of SSH and Codex proxy configurations. When the GitHub API is rate-limited, MyTerm tries the public release page and provides a link to release notes. Failed lookups and incompatible installers are reported explicitly. The app must be named `MyTerm.app` in a writable location; `/Applications/MyTerm.app` is recommended. An app on a read-only DMG cannot update in place. Only newer stable releases are offered, never downgrades or prereleases. Cancel or close the update window to stop downloading or preparation.

## SSH connections

Startup shows a welcome page without opening a local shell. Create an SSH configuration or double-click a saved server in the sidebar; a single click does not connect. The SSH editor supports resizing, maximizing and scrolling, with persistent save controls.

- **Authentication:** automatic, password or key. Automatic uses OpenSSH's selection; password uses password/keyboard-interactive authentication; key uses public-key authentication with a selected private key, SSH agent or SSH configuration.
- **Jump hosts:** configure ordered hops with individual addresses, ports, users, authentication modes and keys. Optionally enter a password with an explicit username; blank reuses a saved password or asks when connecting. Choose Existing Jump Host references shared definitions one hop at a time; Change Jump Host replaces just one hop. Lists include authentication modes and referencing sessions to distinguish profiles sharing an address. Shared edits list referencing sessions and request confirmation; use Save as an independent jump profile first for separate changes. Removing a hop only removes that session’s reference. Existing SSH jump definitions are also supported.
- **Proxy:** unauthenticated HTTP CONNECT or SOCKS5. Proxies can be combined with jump hosts and apply to the first hop.
- **Compression:** enabled by default, configurable per server.
- **Forwarding:** multiple local `-L`, remote `-R` and dynamic SOCKS `-D` rules, listening on `127.0.0.1` by default. Use Add to create a rule and Remove forwarding on that rule to remove it. Save, then open a new SSH connection from the updated configuration; existing connections are unchanged. Rules end with the connection; listener failures terminate connection setup. Remote listener scope also depends on server configuration.
- **Debugging:** optional `ssh -vvv`-style output, off by default.
- **Keepalive:** `ServerAliveInterval=30`, `ServerAliveCountMax=6`, `TCPKeepAlive=yes`. Keepalives cannot prevent a real network outage.

On the first legacy configuration load, MyTerm saves the original bytes as `~/Library/Application Support/MyTerm/servers.json.before-shared-jumps-<UUID>.bak`, then merges detailed hops with identical routes, addresses, ports, users, authentication modes and key settings into shared references. Session IDs, hop row IDs and encrypted credential indexes remain unchanged. Different settings are not merged; string-based SSH jump aliases remain managed by OpenSSH. Corruption or migration failure leaves the original file intact. Shared definitions are stored centrally in the new `servers.json` format. Edits apply to new connections and reconnections without interrupting active transports. Versions predating shared jump profiles cannot read this storage format; to downgrade, quit the app, preserve the current configuration separately, then restore the backup. Versions without an independent jump library may also discard unused profiles when saving; restore these profiles with a version supporting jump host management. Session exports and preferences backups retain reference IDs and self-contained configuration snapshots.

Destination and jump-host password fields start masked. Show password / Hide password lets you verify the current draft; saved passwords are not prefilled, and blank still retains existing credentials. Visibility is not persisted and resets when the editor closes.

Interactive SSH uses `-e none` so sequences such as `~.` reach remote consoles such as ipmitool. Use `exit` or close the tab to end SSH. Connection arguments use `StrictHostKeyChecking=no`.

Import selected Host aliases from `~/.ssh/config` through the sidebar or `⌘⇧I`. The importer supports ordinary Include directives, file globs and recursion protection; it skips wildcard Host patterns and duplicate aliases. Import does not execute Match exec or expand environment variables/percent tokens in Include paths. OpenSSH reads the actual configuration when connecting to a saved alias.

### X11 forwarding

Select disabled, untrusted (`-X`) or trusted (`-Y`) forwarding in the SSH editor. It is disabled by default and must be explicitly enabled per session. XQuartz must be installed and running locally, and the remote sshd must permit X11Forwarding. MyTerm reads DISPLAY from the environment or launchctl and prompts to start XQuartz when unavailable. Use trusted forwarding only with trusted servers.

## Tabs and groups

Drag a tab title onto another tab to reorder SSH, local Bash and Codex tabs without reconnecting or changing the selected session. A single click selects a tab; the whole tab, including its padding, accepts clicks. Right-click or Control-click selects the target tab and opens its menu, without a preceding left-click or double-click. Renaming updates the title and tab width immediately. The context menu supports closing, duplicating, editing the tab and log policy; SSH tabs also expose connection editing and reconnection. Duplication opens an independent connection, without copying processes or history.

The right-hand `+` and blank-strip menu offer local sessions, SSH configurations, saved servers and session restoration. Double-click blank tab-strip space to maximize/restore. Sidebar and bottom status bar visibility are independent; the bottom bar starts hidden. SSH tabs have an SFTP button beside `+`, independent of the bottom bar.

| Shortcut | Action |
| --- | --- |
| `⌘T` | New local Bash session |
| `⌘N` | Add server |
| `⌘F` | Search current terminal history |
| `⌘G` / `⌘⇧G` | Next / previous match |
| `⌘W` | Close current pane; the last pane closes its tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Cycle forward/back through tabs |
| `⌃⌘S` | Toggle sidebar |
| `⌘⇧S` | Save the current tab collection |
| `⌘⇧H` / `⌘⇧V` | Split top/bottom / left/right (customizable) |
| `⌘⇧E` | Export current session text |
| `⌘,` | Settings |

The sidebar uses a two-level **group → session** tree. Groups can be expanded, collapsed, renamed or deleted. Drop one ungrouped server onto another to name a new group containing both; cancelling changes nothing. Drop into an existing group to move a member, or onto the Ungrouped header/footer to remove membership. The context menu offers the same moves. Deleting a group preserves server definitions. Search matches group/server names, addresses and users, expanding matching entries.

Saved tab collections can be restored, renamed, updated or deleted. They retain order, connection definitions, the active pane and local directories, up to 100 sessions including split panes. An exit snapshot is saved when quitting. Restoration appends tabs and establishes new connections; it does not restore processes or feed old text into the terminal. Use tmux when remote programs must survive disconnection.

Normal Bash/SSH exits close their panes; the last pane closes its tab. Unexpected SSH disconnects retain output; focus the terminal and press `R`/`r`, or use Reconnect. Local Bash runs as an interactive login shell and follows `~/.profile` and Bash startup rules. Local directory tracking uses OSC 7; otherwise the initial directory is retained.

### Terminal history search

Use `⌘F` or the tab context menu’s **Search terminal history…** to open search in the active pane. Enter text and press Return to find next, or Shift+Return to find previous; arrow buttons and `⌘G` / `⌘⇧G` also navigate. Options provide case-sensitive, whole-word and regular-expression matching. Matches are selected and revealed, with explicit no-match feedback. Esc or the close button closes search and returns focus to the terminal.

Search defaults to literal text (up to 4096 characters). Enable regular expressions in Options if needed; invalid patterns display an error. It searches the terminal’s retained memory buffer without enabling logging, reading disk history or sending the search text to SSH/local processes. Chinese and soft-wrapped text are supported; navigate again after a font or window resize. Searches run only on Return, navigation shortcuts or arrow clicks; ongoing output does not trigger rescanning. Full-screen programs expose only rendered buffer content, not unseen history inside tmux/less. Output already evicted by history limits cannot be searched.

### Tab colors and environment labels

Use **Edit Tab…** in the tab or split-pane menu to edit the current tab name, color and environment label together. SSH configuration also provides color and environment settings, such as red `PROD` or green `TEST`. Labels support up to 24 characters. Tabs show a color stripe and text; split-pane headers also show the identification. Clear the text and select Default to reset. These are visual identifiers only: connection addresses, authentication and execution permissions are unchanged.

Saved SSH configurations persist the identification and update open tabs sharing that configuration. Temporary SSH, local and Codex tabs can also be labeled; their metadata is retained in saved session snapshots. Duplicated connections and direct splits inherit it. MyTerm JSON session exports/imports and preferences backups retain the metadata; OpenSSH configuration does not carry these UI fields. Tab titles and environment labels are independent.

### Split panes within a tab

Use `⌘⇧H` for top/bottom and `⌘⇧V` for left/right splits, or use the Window menu or tab context menu. By default, split the focused pane directly: local Bash opens an independent Bash in the same directory, and SSH opens an independent connection with the current connection configuration, without a chooser. Use Split Top/Bottom and Choose Session… or Split Left/Right and Choose Session… to connect a saved server or move an existing SSH, local Shell or Codex session. Codex panes still show the chooser to avoid implicitly duplicating AI tasks. Moving retains the process, output and session ID; duplicating SSH creates an independent connection.

Panes can be split again: each new split halves only the selected region, preserving other panes and manually adjusted divider proportions. Window resizing retains those proportions. Drag dividers to resize panes. Enlarge the window when a pane is too small. Click a terminal or pane title to focus it; the title dot marks the active pane. The top-right SFTP control follows the active pane and opens a separate window while split, preserving terminal space. Codex execution controls scroll horizontally in narrow panes. A pane’s close button and `⌘W` close that pane and expand the remaining panes; a tab’s close button closes all its panes. Move to Separate Tab detaches a pane. Tab switching remembers the last active pane, and Codex authorization stays scoped to each session.

**Settings → Terminal Behavior → Split Pane Shortcuts** supports Command plus other modifiers and one letter, detects duplicates and common shortcut conflicts, and restores defaults. `⌘V` still pastes. The former `⌘⇧H` history shortcut now creates a split; history remains available from the File menu or sidebar.

Saved sessions and preferences backups retain split structure and the selected pane. Restore creates new connections; it does not restore terminal processes, running Codex instances or exact divider proportions.

### Broadcast commands to panes

Click Broadcast Command (the antenna icon) at the top right of a split tab, or open it from a pane menu. No targets are selected by default. Select SSH or local Bash panes in the current tab; selected panes show a broadcast marker. Enter a single-line command (up to 4096 bytes, without newlines or control characters), confirm every target is at an empty shell prompt, then click Send and Execute. Each terminal displays its own results. “Sent” means input was submitted, not that the remote command succeeded. After each send, the command is cleared and readiness must be confirmed again. Ordinary keystrokes are not broadcast.

Codex tabs, unauthenticated SSH connections, disconnected sessions and terminals transferring via ZMODEM are unavailable. All targets are revalidated before sending; if any reconnected or became unavailable, nothing is sent. Input is never replayed after reconnection. Broadcasting is not a remote transaction: a network failure after submission may leave some targets having received the command. MyTerm cannot reliably detect Vim, less, password prompts or other interactive programs on the remote host. Return every target to an empty shell prompt first; partially typed input would be combined with the command. Ending broadcast, switching tabs or changing split structure clears the selection. Broadcast configuration is not saved.


## SFTP file management

New SSH tabs immediately expose the SFTP button, while the panel starts hidden. Finish SSH login, open the panel and click Connect. SFTP reuses the authenticated SSH connection; Disconnect ends SFTP without closing the SSH terminal.

- Click to select files/folders; use Command/Shift for multiple selection. Double-click a directory or enter a path to navigate.
- Use toolbar/context-menu downloads, batch uploads/downloads and recursive folders, including empty directories and hidden files.
- Drop files/folders from Finder into the current remote directory, or drag selected remote items to Finder to download.
- Pop the panel into a resizable window. Closing/docking restores the inline panel while retaining connection and selection. The tab-strip button brings an existing detached window forward.
- Transfers run sequentially and show the current file, progress and rate. File conflicts and recoverable operation errors keep SFTP connected; broken connections are closed. The panel Cancel button disconnects and preserves resume files, while Cancel Upload in a conflict dialog stops only the batch.

Uploads merge existing directories. Existing files offer Overwrite, Skip, Overwrite All or Skip All; all choices apply only to this batch, including recursive children. Incompatible types allow only skipping or cancellation. Overwrites finish the temporary upload before replacing the target, atomically with the OpenSSH extension or using a temporary backup otherwise. Failed replacement attempts restore the original; failed restoration reports the backup path. Download directory retries skip completed files only after byte comparison. Downloads offer per-file Overwrite, Skip, Overwrite All and Skip All, and merge directories. Overwriting preserves matching resume temporary files; the completed destination is replaced only after a successful download. Symlinks and special files are never followed; conflicts can be skipped, and other unsupported types fail. Recursion is bounded at 128 levels and 100,000 entries per selected root. Names use UTF-8. The file panel uses SFTP; it has no SCP option.

SFTP drags to Finder use macOS file promises. If Finder assigns a different destination name, MyTerm must honor it. To overwrite the original name or resume reliably, use the panel’s **Download / Resume** action and the same destination path.

### Resume interrupted transfers

Reconnect SFTP and select the **same source and destination**. Uploads use remote `.myterm-part` files with JSON metadata; downloads use local `.filename.myterm-part` files with JSON metadata. Final names are committed after completion. Keep these files and do not modify the source while transferring or resuming.

Uploads verify source SHA-256. Download resume validates connection identity, remote path, size and modification time, not a remote whole-file hash. Mismatching metadata prevents resume. Completed batch items remain; fix the error and select unfinished items or retry the directory.

Rates reflect newly transferred bytes for the current file, excluding bytes completed before resume. Values update periodically with smoothing; completion shows an average.

## ZMODEM and trzsz

### ZMODEM

Both local and remote systems need `rz`/`sz`; see Optional dependencies above for installation.

MyTerm searches `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`; lrzsz is not bundled. Remote `sz filename` asks for a local receive directory; `rz` asks for local upload files. Downloads first receive into private staging, then offer Overwrite, Skip, Overwrite All or Skip All for existing local files without suffixing names. Retained partial files for the same SSH configuration and destination can be resumed or restarted. ZMODEM resume requires you to confirm that the source is unchanged; it does not provide SFTP identity/metadata validation. Uploads default to overwrite with an explicit resume choice, subject to the remote receiver. Retained staging files under Application Support/MyTerm/ZmodemPartial are available for retry. The transfer bar shows status, speed and cancellation. Rates include protocol overhead and retries.

Dropping ordinary files into an authenticated SSH **terminal** clears the unsubmitted command line, invokes the transfer command and waits for a handshake. Stay at a shell prompt, not inside an editor. Missing tools or handshake timeout produce an error. Terminal drops and SFTP panel drops are separate transfer paths.

### trzsz and tmux

SSH enables the bundled trzsz client by default. The remote host needs [trzsz-go](https://github.com/trzsz/trzsz-go) `trz`/`tsz`. Run `trz` to upload, `tsz filename` to download, and `trz -d`/`tsz -d directory` for directories. Ctrl+C cancels.

ZMODEM is unsuitable inside tmux. Automatic terminal-drop mode uses ZMODEM on the normal screen and trzsz on the alternate screen. The SSH editor can force trzsz or disable it. Alternate-screen detection cannot distinguish tmux from vim: return to a shell prompt before dropping. Changes apply to newly opened connections.

Configured ProxyJump chains retain their routing. When manually SSHing onward from an intermediate host's tmux, install trzsz there and use `trzsz --relay ssh target`. The client honors `~/.trzsz.conf`; transfer processing precedes terminal character decoding.

## Codex integration

SSH analysis tabs do not proactively read earlier SSH output on launch by default. Enable **Read existing output when connecting** in the session chooser for an initial history review. Without it, Codex waits for your task; a local cursor baseline distinguishes subsequent output without sending the initial snapshot to Codex. This is a startup workflow preference, not a history-access permission boundary. You can explicitly request earlier history later. Cursor resets or truncated terminal snapshots must be reported as coverage gaps; executed commands still require every `command_status` page through `all_output_delivered=true`.

Open **MyTerm → Codex Integration**. **Codex Configuration** contains CLI path, login, independent proxy tests and external MCP registration. **SSH Session Access** controls session selection, history scope and execution authorization. **Local Work** starts local Codex directly in a chosen directory.

Start a Codex tab and select an open SSH session. Command execution is selected by default with the configured approval mode; uncheck it for read-only access. Output is read on demand, without automatic background monitoring. Authorized multi-step command troubleshooting and explicitly requested periodic checks with a defined interval/count remain available. History supports configurable scopes and pagination, but cannot recover text already removed from the terminal buffer. Disk logging is not required.

Confirming startup authorizes SSH execution when selected with an adjustable duration and command budget; renew in the same tab when exhausted. Commands require individual approval by default. Switch to **Always allow for this session**, or back to per-command approval, at any time. Revocation/expiry clears persistent permission. Plans appear only in the Codex terminal; MyTerm does not capture or duplicate them. MyTerm executes commands through an independent channel and requires complete output delivery before the next command; that channel does not share the terminal's working directory, environment or tmux state.

Codex HTTP/SOCKS5 proxies are separate from SSH proxies. Internal startup prompts automatically include the selected live session ID; no manual copying is needed. External clients discover authorized sessions through `list_sessions`. External MCP adapters belong to their Codex/IDE caller and exit when their communication pipe closes; their presence alone does not mean the GUI is still running.

In the session chooser under **Codex Integration → SSH Session Access → Open Codex tab**, configure command length (256–32768 UTF-8 bytes), timeout (1–3600 seconds), output capacity (1–8 MiB) and approval mode (per-command / session Always Allow). Initial defaults remain 4096 bytes, 60 seconds, 1 MiB and per-command approval. Valid defaults are saved automatically and included in preferences backups. Execution settings are no longer duplicated on the access page; the launch form scrolls while Cancel and Confirm and launch remain visible in a fixed footer. Defaults affect new tabs only. For an existing tab, open Execution Settings and choose Apply and Renew to cancel the current command, reset the budget and apply changes. Ordinary renewal retains that tab’s limits and mode. Larger output capacities consume more memory and model context.

To resume troubleshooting, reopen SSH, select the current SSH tab and cluster, then choose **Continue an existing cluster conversation**. For older chats outside the cluster index, enable **Resume from all Codex history (legacy picker)** and choose a conversation in Codex’s native picker. MyTerm reuses its configured proxy. This restores the Codex conversation, not the old SSH transport. A fresh association binds to the current SSH UUID, even after MyTerm restarts. `list_sessions` returns the current UUID, connection instructions and authorization status; requests using an old UUID are rejected with rediscovery guidance. Old authorizations, job IDs and unfinished commands are not reused as current jobs. Check the target before asking to continue. Output already in the conversation remains historical context; **Read existing output when connecting** only controls the intent to read the current SSH terminal’s history. Codex owns the conversation history; MyTerm maintains only a cluster index without copying conversation files. The legacy picker requires a CLI supporting `codex resume --all`. See the [official Codex resume reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli#codex-resume).

The execution bar fills its pane with one background: SSH Execution on the left, authorization status/renewal/approval controls in the middle, and Execution Settings on the right. Narrow split panes retain horizontal scrolling.


Renewal, approval mode and settings appear on one row, with horizontal scrolling in narrow windows or split panes. The expandable execution history and permanent Stop button are removed; Cancel Current Command appears while work is running or queued. Closing the Codex tab ends its authorization. Cancelling the independent channel may not stop detached remote background processes. Incomplete output still blocks subsequent commands; `incomplete_reason` distinguishes `output_limit`, `timeout`, `cancelled` and `output_read_error`. Explain missing output, then narrow the query or adjust limits and renew; do not ignore the incomplete flag.

SSH commands support multiline scripts (LF newlines and tabs, up to 4096 UTF-8 bytes by default), approved as one submission. Command timeout defaults to 60 seconds and output capacity to 1 MiB; all three limits are configurable.

Multiple Codex tabs can use one SSH tab with independent authorization, quotas, approval and output progress. Renewing, stopping or closing one Codex tab leaves the others intact. Approved commands on the same SSH connection run serially; waiting does not require reauthorization. Closing or disconnecting SSH invalidates the associated execution grants. External MCP clients can read shared sessions but cannot reuse internal execution grants.

Execution tools return compact metadata by default while retaining full output and approval state. With no new output, `command_status` waits up to 20 seconds; pages contain up to 16 KiB to reduce repeated calls. Ask Codex to query an existing job with `verbose=true` for details without rerunning it. Codex still controls how tool names and arguments are displayed.

See the [Codex integration guide](docs/CODEX-INTEGRATION.en.md) for workflow, queue states and limits.

### Organize Codex conversations by cluster

SSH connection setup provides a Default project (stored as `Default`), so creating a cluster first is optional. Existing clusters remain selectable and saved SSH-to-cluster associations are retained. The default project can be managed and deleted like any cluster; using the default entry again recreates it as needed. Select an SSH connection and optionally choose or create a cluster such as GMI Dallas. SSH head nodes are connection entry points: a cluster may use different head nodes, and one SSH connection may serve different clusters. MyTerm remembers the last cluster selected for a saved SSH configuration; verify it before starting.

Opening the chooser with the default project starts a new conversation. When explicitly selecting a cluster or recalling a saved SSH association, its most recently opened conversation is selected for continuation if available. Turn off Continue an existing cluster conversation to create a new one. The default name is Daily operations; a conversation may cover multiple topics across days. Names omit dates unless duplicated, when `MM-dd HH:mm:ss` is appended; a same-second collision uses milliseconds, never `(1)` or `(2)`. MyTerm labels the tab `Codex · Cluster · Conversation`. Use `/rename` inside Codex to rename it; MyTerm reads the official title on the next resume. Until then the list shows the last recorded title; its date is the last opening from MyTerm.

Names are persisted through official `thread/name/set`; resume uses the Codex thread UUID rather than a temporary SSH tab UUID. Every resume creates fresh SSH association and authorization; confirm the target before continuing an old task. MyTerm prevents opening one managed conversation in multiple tabs to avoid mixing SSH contexts; create separate conversations for parallel tasks.

Per-cluster directories default to `~/Library/Application Support/MyTerm/CodexProjects/`. On the launch page, use “Storage directory for new clusters → Choose directory…” to select a location or restore the default. Changes apply only to newly created clusters. Existing clusters retain their original paths, shown as the current cluster directory; files and Codex historical working directories are not migrated. Organizational metadata remains in `codex-clusters.json` under MyTerm’s application support directory. Codex still owns history and login; its database is not copied or edited. This directory is local project context, not a remote SSH directory, and does not expand local write permissions. This feature requires a CLI supporting `thread/start`, `thread/name/set` and `thread/read`. Preparation uses the independent Codex proxy without model requests; actual conversations still consume usage normally.

MyTerm maintains its cluster and conversation list independently, so deleting a conversation in Codex does not automatically remove its local entry. Select an entry and use “Remove conversation entry”, or use “Delete cluster” to remove the cluster, its local conversation entries and remembered SSH-to-cluster associations. Both require confirmation and remove only MyTerm metadata, preserving Codex history and all project files. Close open conversation tabs before removal. SSH configurations are preserved.

The cluster list contains conversations created through this entry point. Resume from all Codex history (legacy picker) remains available for old chats. They are not automatically renamed or migrated, and automatic desktop project-sidebar creation is not guaranteed. The cluster index and Codex history are not included in MyTerm preferences backups. Moving to another computer also requires transferring Codex history and handling directory changes; copying the index alone cannot restore chats.

### Standalone local Codex

Open **MyTerm → Codex Integration → Local Work**, confirm or choose a working directory, and click **Start Local Codex**. The default is your home directory. No Bash or SSH tab is required, associated or read.

This reuses login and HTTP/SOCKS5 proxy settings from **Codex Configuration**, without changing `~/.profile` or normal Bash/SSH proxies. Local mode disables MyTerm MCP and does not depend on external registration or terminal sharing. If login is needed, startup continues after login; successful startup closes the configuration window.

Local commands and file operations use Codex native tools with the `workspace-write` sandbox and `on-request` approvals: the selected directory is writable, and MyTerm does not ask for each command. Temporary variables, aliases and running programs in other Bash tabs are not inherited. SSH analysis still uses SSH Session Access and its existing authorization flow.

### Codex display, copy and paste

To keep formatted questions and replies while using MyTerm's direct drag-to-copy behavior, choose **Scrollback** in Codex's TUI mode picker, then exit and restart Codex. This corresponds to `fullscreen_transcript = false` in `~/.codex/config.toml`; it is separate from raw output mode (`raw_output_mode`):

```toml
[tui]
fullscreen_transcript = false
```

Settings, Codex integration and SSH configuration windows move to the active desktop when opened. Codex tabs use ordinary terminal scroll routing: when a process requests mouse reporting, it receives scrolling; otherwise MyTerm scrolls local history. MyTerm no longer forcibly intercepts wheel events in Codex normal buffers. Copy and right-click paste settings remain unchanged. History remains subject to line and memory limits.

Known issue: scrolling through history while Codex continues producing output can still jump to much earlier content. The forced scrolling override in 3.3.3 did not resolve this and was reported to make it worse; it has been reverted. The original issue still needs investigation.

In the ordinary conversation view of Codex CLI 0.157.1, Scrollback does not enable mouse reporting. With MyTerm selection-copy enabled, simply drag to select and release the mouse to copy—**no Shift needed**. Right-click still pastes when that option is enabled. In Fullscreen mode or another view that captures the mouse, hold Shift while dragging and until you release the mouse to select locally. Shift+right-click opens the menu.

No additional `raw_output_mode` or `alternate_screen` setting is required: their defaults are `false` and `"auto"`, respectively. If you previously set `raw_output_mode = true` or `alternate_screen = "never"`, remove those overrides or restore the default values. Scrollback does not require raw output mode, which may make questions and replies harder to distinguish. See the [official Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) for defaults and option details.

If a `[tui]` section already exists, update it rather than declaring it again; preserve other settings such as your theme. If you use a custom `CODEX_HOME`, edit `config.toml` in that directory. Save, exit the current Codex session, and run `codex` again; MyTerm does not need to restart. MyTerm's built-in Codex tabs no longer force `--no-alt-screen` and respect Codex's saved display mode; these options do not change SSH execution authorization.

## Terminal display and interaction

**Settings → Language** supports Chinese, English and system language, applied immediately, including system commands such as AutoFill and Center in the Edit and Window menus, without restarting. Settings and Codex Integration use vertical sidebar navigation, a resizable window and independently scrolling content.

**Theme & Font** provides system/dark/light appearance, dark/light presets with palette previews, a font dropdown and **5–36 pt** sizes. Reopen the theme page after installing fonts to refresh the list. Monospace fonts are recommended for terminal tables and tmux. Hold Ctrl and swipe up/down with two fingers to zoom in/out in 0.5 pt steps; momentum scrolling is ignored. With terminal focus, use `⌘+` (or `⌘=`) to enlarge and `⌘-` to shrink in 0.5 pt steps; like trackpad zoom, these update the global terminal font setting.

Additional presets include Night Sky, Northern Night, Soft Mist and Warm Cream, each with a complete ANSI 16-color palette. Cards preview the colors; clicking applies them while retaining the font, size and background opacity. These MyTerm palettes are inspired by [TerminalColors dark themes](https://terminalcolors.com/tags/dark/) and the [light-theme collection](https://gist.github.com/lr580/7ec84df732e0946f03504d7fe02387c0), rather than exact copies of those themes.

Edit foreground/background, cursor/cursor text, selection colors and ANSI 16 colors using the system color picker, HEX input, preview or `.itermcolors` import/export. Imports preserve font, size and opacity; missing colors remain unchanged. Background opacity defaults to 100% and affects only the default background/padding, not text or program-specified backgrounds. ANSI palette edits do not rewrite RGB truecolor output.

**Output Highlighting** supports keywords, colors, priority, whole-word matching and case sensitivity. Defaults color SSH error/success/warning words red/green/yellow on the normal screen while preserving remote ANSI colors. Local terminals and full-screen programs can be enabled separately. Highlighting affects display only, not copied, exported or transferred data. Horizontal padding is included in terminal-width calculations.

**Terminal Behavior** controls selection-copy, right-click paste and bell. Selection-copy/right-click paste are enabled and the bell disabled by default. Shift+right-click always opens the menu; `⌘C`/`⌘V` remain available.

**Settings → Terminal Behavior → Full-screen trackpad scrolling** offers Standard, Fast (4×, default) and Page Up / Page Down. Enter tmux copy mode (`Ctrl+B`, then `[`) to browse with two fingers. Page mode sends page keys in the scroll direction, ignores momentum and rate-limits paging. The terminal cannot reliably identify tmux copy mode, so this setting also affects other full-screen programs. Normal shell history, mouse wheels, Shift scrolling and Ctrl font zoom retain their existing behavior.

MyTerm disables the macOS press-and-hold accent menu within the app. Holding letters such as `h/j/k/l` with an English input source repeats them for Vim navigation. Global preferences are unchanged, and Chinese composition still uses the input method. Repeat speed and delay follow macOS keyboard settings.

The first double-click selects whitespace-delimited text; double-click the selection again to expand to a logical line. Copy joins recorded soft wraps and preserves hard newlines. Use Copy with Screen Line Breaks to retain visual layout, or Shift to select locally when the remote program captures mouse events. Full-screen redraws without wrap metadata may still copy as separate screen lines.

The bottom bar offers UTF-8, GB2312, GBK, GB18030, Big5, Shift-JIS, EUC-KR and ISO-8859-1. Changes affect subsequent input/output; unrepresentable characters use replacements. Binary transfers are unaffected.

### tmux and screen sharing

New PTYs use `xterm-256color` and clear inherited TMUX, TMUX_PANE, LINES and COLUMNS variables. Remote shells/tmux require a valid UTF-8 locale. Do not unconditionally override TERM in shell startup files. One ordinary key after the default Ctrl+B prefix uses an ASCII keyboard layout, allowing tmux shortcuts under a Chinese input method without changing later Chinese input. Custom prefixes are not detected.

Layout updates are coalesced, zero sizes ignored and dimensions measured in AppKit logical points. Lock Size in the bottom bar holds terminal dimensions while resizing or toggling panels; smaller windows can scroll the terminal region. Disable it to resume automatic sizing. Font changes still affect rows/columns; the setting does not control other remote tmux clients or conferencing capture behavior.

## History and logs

Scrollback has a separate global memory budget: **256 MiB** by default, shared equally across all terminal tabs, including retained exited tabs. Set **Settings → Terminal Behavior → History memory budget** to 16–16,384 MiB, or **0** to use only the line limit. Capacity is estimated from row width and character storage cost and also respects the per-session line limit. This is not a hard limit on process memory; visible screens, images and UI are excluded. Opening more tabs, widening windows or lowering the budget may discard oldest scrollback permanently. Existing disk logs are unaffected, and disabling logging does not disable in-memory scrollback.

**Disk logging is off by default.** Configure the global default under Terminal Behavior, or choose inherit/always save/do not save in an SSH configuration or tab menu.

Scrollback/saved history defaults to 50,000 lines and is adjustable. Default limits are 20 MiB per history file and 500 MiB total. Fast gzip compression is enabled by default; compression and disk work run in the background. Limits use compressed file size, retaining newer text and pruning the least recently updated records.

When enabled, history snapshots are saved every 30 seconds, on tab close and on application exit under `~/Library/Application Support/MyTerm/History/`. They are not unlimited logs or recordings. Cleared/evicted text cannot be recovered; full-screen programs contribute only their current screen. Crashes may lose unsaved snapshots.

**File → Session History** supports filtering, searching, exporting, deleting and clearing records older than 30 days or all records. Deleting an active session's record prevents its recreation during that connection. **Export Current Session Text** writes UTF-8 without ANSI controls or wide-character placeholders and works independently of automatic logging.

## Passwords and keys

Select an authentication mode first: Password shows only the password input, Key shows only the private-key selector, and Automatic uses SSH configuration and existing credentials without showing credential inputs. Switching modes preserves existing settings; password mode does not pass a private-key file. Password entry is optional and requires an explicit username. Save writes them to the local encrypted database; blank retains the saved password or asks when connecting. Key authentication ignores this input. Passwords can also be entered in the authentication dialog. With Remember after Successful Login selected, they are stored only after successful authentication, reused later, and replaced when rejected. Changing names, logging, compression or port forwarding preserves password associations. Recognized destination-server prompts are scoped to the session, host, user, port and jump route; custom prompts are one-time only. Pre-entered passwords are used only for ordinary prompts matching the username and host; prompts changed by SSH alias resolution or ambiguous endpoints still require interaction. Key passphrases and verification codes are not saved automatically.

Detailed jump passwords are shared by address, port, username, preceding hops and network proxy, independently of the destination session. Passwords entered in the editor are encrypted locally when Save is clicked; blank keeps the existing password. Passwords remembered during authentication are stored after successful login. Password management shows referencing sessions; replacing a shared password affects subsequent connections using that route. Secrets are excluded from session JSON and OpenSSH exports. Ambiguous prompts or unspecified usernames still require interactive authentication.

**Settings → SSH Passwords** supports names, session associations, updates, removal and clearing. Updates change only local records. Revealing a password requires a click; leaving the page or losing window focus hides it. Passwords do not enter terminal history, server JSON, process arguments or environment variables.

Credentials use app-managed SQLite with CryptoKit AES-256-GCM, without system Keychain access. Files are `passwords.sqlite` and `encryption.key` under `~/Library/Application Support/MyTerm/Credentials/`, with directory permissions 0700 and file permissions 0600. The key is local to support automatic login without a master password; a process able to read both files can decrypt them. Manual backups need both.

**Settings → SSH Keys** imports OpenSSH/PEM private keys, including encrypted formats, displays public keys and deletes managed copies. Authentication still depends on system OpenSSH, server algorithms and hardware key devices. Import preserves bytes and a matching `.pub`, without deleting originals or stripping passphrases. Keys live under `~/Library/Application Support/MyTerm/Keys/`; select them from the editor's key library or reference external files directly.

The key list shows explicit references from servers, saved sessions, active tabs and jump hosts. Deleting a referenced key requires extra confirmation. External programs and implicit references in SSH configuration are not counted.

### Jump host management and testing

Open Settings → Jump Host Manager (the SSH editor shortcut opens the same settings page) to add, search, edit and delete unused, single-session or shared jump hosts. Unused profiles remain saved independently; existing hops appear automatically. Editing referenced profiles requires impact confirmation. Remove references from sidebar sessions, saved snapshots and open tabs before deleting. Password and automatic authentication expose a password field with show/hide. Saving encrypts the password for direct access and currently referencing session routes; blank preserves existing credentials. Tests can use an unsaved password without persisting it. New routes with different proxies or preceding hops may still need a password. Profiles are included in session JSON import/export and encrypted preferences backups; OpenSSH export includes only hops actually referenced by sidebar sessions.

Jump hosts support custom names in Settings → Jump Host Manager and the SSH editor. Empty names fall back to the host address. Lists and selection menus show names, and search includes names. Names persist through shared references, session import/export and backups; renaming does not change connections or password identifiers.

In the SSH editor, Choose Existing Jump Host appends a saved hop; Change Jump Host replaces one. Multiple hops retain their order; save a separate profile when edits should affect only one session.

Test Connection appears above the reference list and verifies real SSH connectivity and authentication, either directly or via a referencing session’s preceding hops and proxy. It executes no remote commands and supports Windows and forwarding-only jump hosts. It times out after 45 seconds and can be cancelled. It changes no remote files. Success does not guarantee TCP forwarding permission or reachability of subsequent targets. Failure details appear in the window.

## Configuration and backups

`servers.json`, `groups.json` and `sessions.json` under `~/Library/Application Support/MyTerm/` store servers, groups and saved tab collections. Group changes do not alter authentication or live connections. Invalid configuration originals are preserved; damaged group data can be repaired or removed through the recovery prompt.

- **Session configuration export/import:** versioned JSON for servers, groups and saved tab collections. Save active tabs first. Passwords, private-key files and history are excluded. Import does not connect; identical records are skipped, conflicts/invalid input cancel the import. Maximum file size: 20 MB.

- **OpenSSH export:** exports File-menu configurations for `ssh -F /path/to/config HostAlias`, including authentication, jumps, proxies and forwarding. Include references are retained. Keys, aliases and proxy helpers must be supplied on the destination Mac; this is not a self-contained backup. Sessions sharing a host receive stable `myterm-session-name-short-id` export aliases and retain the original destination as `HostName`; unique hosts keep their names. Generated aliases use safe ASCII characters and fall back to the host when the session name has no usable ASCII characters. Comments retain full session names; export does not change saved sessions. If settings are inherited from an external `Host original-alias` block, make them match the generated alias too. If the destination itself is an SSH alias, set the exported block’s `HostName` to its actual target.

Detailed jumps are deduplicated by effective connection settings. Export aliases use `myterm-jump-name-short-id`; comments retain full names and referencing sessions, including non-ASCII names. A shared jump with identical settings is emitted once; different proxy, authentication, compression or logging settings remain separate. Multi-hop order is preserved and export does not change runtime connection settings.
- **Preferences backup/restore:** password-encrypted `.mytermbackup` includes servers, groups, saved sessions, active-tab configuration snapshots, appearance/language/terminal preferences, SSH passwords and managed keys. History, external SSH configuration/keys and installed fonts are excluded, as is the separate Codex proxy-password store.

Use File → SSH Configuration Check & Export… to inspect references from sidebar sessions, jumps, saved snapshots and open tabs. The report marks export scope, saved-password presence, explicit key-file existence/readability and credentials without known references for manual review. It reads no password or private-key contents and deletes nothing. External SSH configuration, Include, default keys and agents are not resolved, so this is not a login guarantee. Checking and exporting share one window. Export OpenSSH Configuration… selects the output file; cancelling the file picker keeps the report open. Export uses the sidebar configuration captured for the preview; Refresh captures it again.

Backups use a password-derived key and AES-256-GCM integrity protection. Lost backup passwords cannot be recovered. Restore validates first, then confirms configuration replacement and closes connections; failed writes attempt rollback. Managed-key paths adapt to the destination home directory. Restart after restoring to apply all preferences.

## Diagnosing terminal issues

For intermittent scrolling or Enter-key problems, open **Help → Terminal Diagnostics…**:

1. Click **Start New Capture** before reproducing the issue, then return to the affected tab.
2. After the issue occurs, click **Mark Incident**, then **Stop Recording**.
3. Choose **Export Diagnostics…** and share the ZIP with the incident time, reproduction steps, and expected versus actual behavior. Also specify the Codex CLI version (`codex --version`), input method, and whether tmux was involved.

Terminal event recording is off by default. Each capture lasts up to 15 minutes and retains the latest 5,000 events in memory. Quitting clears it; starting a new capture replaces the previous one. Closing the diagnostic window does not stop recording. Nothing is uploaded automatically. Exports contain app/macOS versions, process peak resident memory, anonymous terminal identifiers/types, scrolling/selection/focus state, keyboard protocol flags, Return events, and byte counts. They exclude input/output text, passwords, tokens, hostnames, and configuration files. Output events are sampled and aggregated, not a complete traffic count.

This helps determine whether MyTerm received Return, reached its send path, and followed output. It cannot prove that Codex processed a key or establish a memory leak from one snapshot. Diagnostics do not replace optional session text logs; review any separate screenshots or text logs for sensitive information before sharing them.

For MCP handshake failures, start recording before opening a Codex tab associated with SSH, then reproduce, stop and export. The `mcp` field contains helper PID/parent PID, timestamps, initialization/tool-discovery stages, stdin EOF, input-limit failures and pipe read/write error numbers; it excludes protocol bodies, commands and credentials. MCP metadata is stored in `~/Library/Application Support/MyTerm/mcp-diagnostics.json` (owner-only access), bounded to 256 entries and the same 15-minute capture window. Clearing or starting a new capture replaces it; it remains exportable after quitting. A process that fails to launch or is forcibly terminated may have no exit event; its last event alone does not prove the exit cause. Include the incident time and Codex version.

Codex path, proxy, login and MCP checks belong to Codex Configuration. SSH Session Access no longer repeats dependency or healthy-configuration descriptions; only invalid configuration shows its reason and a return-to-configuration button. Startup validation and automatic login checks remain enabled. Signature and Gatekeeper observations remain in diagnostic exports only; they do not determine MCP health.

In **Codex configuration → SSH MCP interface → Check SSH MCP interface**, test the actual bundled helper initialization and tool discovery. The timestamped result is separate from login, proxy and external registration checks. Failures show the stage and reason/code. No SSH outputs or commands are accessed; success does not verify the external Codex environment, GUI bridge authorization or remote SSH connectivity. Use Terminal Diagnostics for intermittent failures.

See [macOS permissions and security checks](docs/PERMISSIONS.en.md) for required versus conditional permissions, signature/Gatekeeper diagnostics and their limits. Do not grant Full Disk Access or Accessibility as a generic MCP fix.

Diagnostic archives include `诊断摘要.txt` (Chinese) and `Diagnostic-Summary.en.txt` (English). Read these first for observed stages, impact, next steps and limits of the evidence. `diagnostic.json` retains raw codes and the timestamped `mcpHealth` check result. The Codex interface check also displays a readable explanation, with numeric details collapsed. A normal EOF or a failed Gatekeeper assessment alone is not classified as a root cause. Explicit checks and captured helper events are described separately; missing events are not proof of success. Summaries use fixed local rules, not a model, and contain no terminal text or credentials.

## Build and package from source

Building requires macOS 14+ and Swift 6.0+. Run from the repository root:

```bash
bash scripts/build-app.sh
open dist/MyTerm.app
```

The default is a Debug app for the current Mac architecture; `bash scripts/build-app.sh release` creates an optimized build. Dependencies are vendored. See the [SwiftTerm patch notes](vendor/SwiftTerm/MYTERM-PATCH.md) and [trzsz notes](vendor/trzsz/1.2.0/README.md) for dependency versions, modifications and notices.

Package and validate an installation:

```bash
bash scripts/package-release.sh
bash scripts/create-dmg.sh
bash scripts/install-release.sh
```

[packaging/Info.plist](packaging/Info.plist) defines the version. Artifacts go into `dist/releases/<version>/`: ZIP, DMG, release notes and SHA-256 checksums. Packaging refuses to overwrite an existing version directory.

The release workflow checks Debug, Release and an app copied from the actual DMG, comparing bundle files, permissions and symlinks. Installation copies that validated app to `/Applications/MyTerm.app`, verifies its contents, signature and window behavior, then opens it and synchronizes `dist/MyTerm.app` to the same bundle. Failed installation validation restores the previous app.

## Tests and source

For handoff and long-term decisions, read the [development context](docs/DEVELOPMENT-CONTEXT.en.md) and [workflow](AGENTS.md). New Codex sessions can use the handoff prompt in that document.

See [Testing and maintenance](docs/TESTING.en.md) for the unified runner, feature coverage and validation limits.


Run from the repository root:

```bash
bash scripts/check.sh
bash scripts/check-integration.sh
```

Core checks cover SSH arguments, configuration, PTYs, process cleanup, MCP, transfer detection and real-SFTP file/directory transfers, resume, conflicts and symlinks. Integration checks use temporary local sshd/proxy/echo services to validate authentication, jumps, forwarding and connection reuse without modifying user SSH configuration.

```bash
python3 scripts/window-controls-check.py dist/MyTerm.app
dist/MyTerm.app/Contents/MacOS/MyTerm --smoke-test --transfer-check
MYTERM_TMUX_CHECK=1 bash scripts/check-integration.sh
MYTERM_TRZSZ_CHECK=1 bash scripts/check-integration.sh
```

Window checks cover menus, tabs, layout, bilingual settings and SFTP interaction. Transfer smoke checks use Debug builds; ZMODEM/tmux tests need the corresponding tools. Password tests use a separate environment and temporary credential store:

```bash
python3 -m venv .test-venv
.test-venv/bin/python -m pip install -r scripts/requirements-password-test.txt
bash scripts/check.sh
.test-venv/bin/python scripts/password-check.py
```

- `Sources/MyTerm`: windows, forms, terminals, transfer UI and in-app checks.
- `Sources/MyTermCore`: SSH configuration, persistence, SFTP, resume and MCP.
- `Sources/MyTermProxy`: HTTP CONNECT/SOCKS5 proxy helper.
- `Tests/MyTermCoreTests`, `scripts/`: core/integration checks, packaging and installation validation.

Version changes belong in the [release history](CHANGELOG.en.md). README documents usage and limits without hardcoding a latest-version number.
