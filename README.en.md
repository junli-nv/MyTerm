# MyTerm

[简体中文](README.md) · English

[Repository](https://github.com/junli-nv/MyTerm) · [Download](https://github.com/junli-nv/MyTerm/releases/latest) · [Release history](CHANGELOG.en.md)

A native macOS SSH workspace built with SwiftUI/AppKit, SwiftTerm and system OpenSSH. It supports local Bash, SSH tabs, session groups, file transfers and Codex integration authorized per SSH session.

## Install and build

Download the DMG for your architecture from the [latest release](https://github.com/junli-nv/MyTerm/releases/latest), open it and drag MyTerm into Applications. The release page and `SHA256SUMS.txt` provide the version, build and checksums. Packages are ad-hoc signed, without Developer ID signing or Apple notarization.

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

## SSH connections

Startup shows a welcome page without opening a local shell. Create an SSH configuration or double-click a saved server in the sidebar; a single click does not connect. The SSH editor supports resizing, maximizing and scrolling, with persistent save controls.

- **Authentication:** automatic, password or key. Automatic uses OpenSSH's selection; password uses password/keyboard-interactive authentication; key uses public-key authentication with a selected private key, SSH agent or SSH configuration.
- **Jump hosts:** configure ordered hops with individual addresses, ports, users, authentication modes and keys. Passwords or key passphrases are requested for each hop. Existing SSH jump definitions are also supported.
- **Proxy:** unauthenticated HTTP CONNECT or SOCKS5. Proxies can be combined with jump hosts and apply to the first hop.
- **Compression:** enabled by default, configurable per server.
- **Forwarding:** multiple local `-L`, remote `-R` and dynamic SOCKS `-D` rules, listening on `127.0.0.1` by default. Rules end with the connection; listener failures terminate connection setup. Remote listener scope also depends on server configuration.
- **Debugging:** optional `ssh -vvv`-style output, off by default.
- **Keepalive:** `ServerAliveInterval=30`, `ServerAliveCountMax=6`, `TCPKeepAlive=yes`. Keepalives cannot prevent a real network outage.

Interactive SSH uses `-e none` so sequences such as `~.` reach remote consoles such as ipmitool. Use `exit` or close the tab to end SSH. Connection arguments use `StrictHostKeyChecking=no`.

Import selected Host aliases from `~/.ssh/config` through the sidebar or `⌘⇧I`. The importer supports ordinary Include directives, file globs and recursion protection; it skips wildcard Host patterns and duplicate aliases. Import does not execute Match exec or expand environment variables/percent tokens in Include paths. OpenSSH reads the actual configuration when connecting to a saved alias.

### X11 forwarding

Select disabled, untrusted (`-X`) or trusted (`-Y`) forwarding in the SSH editor. It is disabled by default and must be explicitly enabled per session. XQuartz must be installed and running locally, and the remote sshd must permit X11Forwarding. MyTerm reads DISPLAY from the environment or launchctl and prompts to start XQuartz when unavailable. Use trusted forwarding only with trusted servers.

## Tabs and groups

Drag a tab title onto another tab to reorder SSH, local Bash and Codex tabs without reconnecting or changing the selected session. The context menu supports closing, duplicating, renaming and log policy; SSH tabs also expose connection editing, reconnection and **Copy Session ID (Codex)**. Duplication opens an independent connection, without copying processes or history.

The right-hand `+` and blank-strip menu offer local sessions, SSH configurations, saved servers and session restoration. Double-click blank tab-strip space to maximize/restore. Sidebar and bottom status bar visibility are independent; the bottom bar starts hidden. SSH tabs have an SFTP button beside `+`, independent of the bottom bar.

| Shortcut | Action |
| --- | --- |
| `⌘T` | New local Bash session |
| `⌘N` | Add server |
| `⌘W` | Close current tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Cycle forward/back through tabs |
| `⌃⌘S` | Toggle sidebar |
| `⌘⇧S` | Save the current tab collection |
| `⌘⇧H` | Open session history |
| `⌘⇧E` | Export current session text |
| `⌘,` | Settings |

The sidebar uses a two-level **group → session** tree. Groups can be expanded, collapsed, renamed or deleted. Drop one ungrouped server onto another to name a new group containing both; cancelling changes nothing. Drop into an existing group to move a member, or onto the Ungrouped header/footer to remove membership. The context menu offers the same moves. Deleting a group preserves server definitions. Search matches group/server names, addresses and users, expanding matching entries.

Saved tab collections can be restored, renamed, updated or deleted. They retain order, connection definitions, selection and local directories, up to 100 tabs. An exit snapshot is saved when quitting. Restoration appends tabs and establishes new connections; it does not restore processes or feed old text into the terminal. Use tmux when remote programs must survive disconnection.

Normal Bash/SSH exits close their tabs. Unexpected SSH disconnects retain output; focus the terminal and press `R`/`r`, or use Reconnect. Local Bash runs as an interactive login shell and follows `~/.profile` and Bash startup rules. Local directory tracking uses OSC 7; otherwise the initial directory is retained.

## SFTP file management

New SSH tabs immediately expose the SFTP button, while the panel starts hidden. Finish SSH login, open the panel and click Connect. SFTP reuses the authenticated SSH connection; Disconnect ends SFTP without closing the SSH terminal.

- Click to select files/folders; use Command/Shift for multiple selection. Double-click a directory or enter a path to navigate.
- Use toolbar/context-menu downloads, batch uploads/downloads and recursive folders, including empty directories and hidden files.
- Drop files/folders from Finder into the current remote directory, or drag selected remote items to Finder to download.
- Pop the panel into a resizable window. Closing/docking restores the inline panel while retaining connection and selection. The tab-strip button brings an existing detached window forward.
- Transfers run sequentially and show the current file, progress and rate. Errors stop the operation. Cancel disconnects SFTP and preserves resume files.

Directory retries merge folders and skip completed files only after byte comparison. Uploads refuse to overwrite different contents. Downloads into existing destinations require save-panel or merge/replace confirmation. Symlinks and special files cause an error rather than being followed. Recursion is bounded at 128 levels and 100,000 entries per selected root. Names use UTF-8. The file panel uses SFTP; it has no SCP option.

### Resume interrupted transfers

Reconnect SFTP and select the **same source and destination**. Uploads use remote `.myterm-part` files with JSON metadata; downloads use local `.filename.myterm-part` files with JSON metadata. Final names are committed after completion. Keep these files and do not modify the source while transferring or resuming.

Uploads verify source SHA-256. Download resume validates connection identity, remote path, size and modification time, not a remote whole-file hash. Mismatching metadata prevents resume. Completed batch items remain; fix the error and select unfinished items or retry the directory.

Rates reflect newly transferred bytes for the current file, excluding bytes completed before resume. Values update periodically with smoothing; completion shows an average.

## ZMODEM and trzsz

### ZMODEM

Both local and remote systems need `rz`/`sz`. Install locally with:

```bash
brew install lrzsz
```

MyTerm searches `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`; lrzsz is not bundled. Remote `sz filename` asks for a local receive directory; `rz` asks for local upload files. Receiving protects existing files; sending requests resume, subject to the remote receiver. The transfer bar shows status, speed and cancellation. Rates include protocol overhead and retries.

Dropping ordinary files into an authenticated SSH **terminal** clears the unsubmitted command line, invokes the transfer command and waits for a handshake. Stay at a shell prompt, not inside an editor. Missing tools or handshake timeout produce an error. Terminal drops and SFTP panel drops are separate transfer paths.

### trzsz and tmux

SSH enables the bundled trzsz client by default. The remote host needs [trzsz-go](https://github.com/trzsz/trzsz-go) `trz`/`tsz`. Run `trz` to upload, `tsz filename` to download, and `trz -d`/`tsz -d directory` for directories. Ctrl+C cancels.

ZMODEM is unsuitable inside tmux. Automatic terminal-drop mode uses ZMODEM on the normal screen and trzsz on the alternate screen. The SSH editor can force trzsz or disable it. Alternate-screen detection cannot distinguish tmux from vim: return to a shell prompt before dropping. Changes apply to newly opened connections.

Configured ProxyJump chains retain their routing. When manually SSHing onward from an intermediate host's tmux, install trzsz there and use `trzsz --relay ssh target`. The client honors `~/.trzsz.conf`; transfer processing precedes terminal character decoding.

## Codex integration

Open **MyTerm → Codex Integration**. **Codex Configuration** contains CLI path, login, independent proxy tests and external MCP registration. **SSH Session Access** controls session selection, history scope, monitoring and execution authorization.

Start a Codex tab and select an open SSH session. Access is read-only by default and continuous monitoring is off until explicitly selected; monitoring can consume model quota. History supports configurable scopes and pagination, but cannot recover text already removed from the terminal buffer. Disk logging is not required.

SSH execution requires separate authorization with an adjustable duration and command budget; renew in the same tab when exhausted. Commands require individual approval by default. Switch to **Always allow for this session**, or back to per-command approval, at any time. Revocation/expiry clears persistent permission. Plans can be expanded, hidden or cancelled. MyTerm executes commands through an independent channel and requires complete output delivery before the next command; that channel does not share the terminal's working directory, environment or tmux state.

Codex HTTP/SOCKS5 proxies are separate from SSH proxies. Internal startup prompts include the selected live session ID; copy it from the SSH tab menu when needed. External MCP adapters belong to their Codex/IDE caller and exit when their communication pipe closes; their presence alone does not mean the GUI is still running.

See the [Codex integration guide](docs/CODEX-INTEGRATION.en.md) for permissions, limits and troubleshooting.

## Terminal display and interaction

**Settings → Language** supports Chinese, English and system language, applied immediately. Settings use fixed tabs.

**Theme & Font** provides system/dark/light appearance, presets, installed-font search, a monospace filter, custom names and **5–36 pt** sizes. Refresh after installing fonts. Monospace fonts are recommended for terminal tables and tmux. Hold Ctrl and swipe up/down with two fingers to zoom in/out in 0.5 pt steps; momentum scrolling is ignored.

Edit foreground/background, cursor/cursor text, selection colors and ANSI 16 colors using the system color picker, HEX input, preview or `.itermcolors` import/export. Imports preserve font, size and opacity; missing colors remain unchanged. Background opacity defaults to 100% and affects only the default background/padding, not text or program-specified backgrounds. ANSI palette edits do not rewrite RGB truecolor output.

**Output Highlighting** supports keywords, colors, priority, whole-word matching and case sensitivity. Defaults color SSH error/success/warning words red/green/yellow on the normal screen while preserving remote ANSI colors. Local terminals and full-screen programs can be enabled separately. Highlighting affects display only, not copied, exported or transferred data. Horizontal padding is included in terminal-width calculations.

**Terminal Behavior** controls selection-copy, right-click paste and bell. Selection-copy/right-click paste are enabled and the bell disabled by default. Shift+right-click always opens the menu; `⌘C`/`⌘V` remain available.

The first double-click selects whitespace-delimited text; double-click the selection again to expand to a logical line. Copy joins recorded soft wraps and preserves hard newlines. Use Copy with Screen Line Breaks to retain visual layout, or Shift to select locally when the remote program captures mouse events. Full-screen redraws without wrap metadata may still copy as separate screen lines.

The bottom bar offers UTF-8, GB2312, GBK, GB18030, Big5, Shift-JIS, EUC-KR and ISO-8859-1. Changes affect subsequent input/output; unrepresentable characters use replacements. Binary transfers are unaffected.

### tmux and screen sharing

New PTYs use `xterm-256color` and clear inherited TMUX, TMUX_PANE, LINES and COLUMNS variables. Remote shells/tmux require a valid UTF-8 locale. Do not unconditionally override TERM in shell startup files. One ordinary key after the default Ctrl+B prefix uses an ASCII keyboard layout, allowing tmux shortcuts under a Chinese input method without changing later Chinese input. Custom prefixes are not detected.

Layout updates are coalesced, zero sizes ignored and dimensions measured in AppKit logical points. Lock Size in the bottom bar holds terminal dimensions while resizing or toggling panels; smaller windows can scroll the terminal region. Disable it to resume automatic sizing. Font changes still affect rows/columns; the setting does not control other remote tmux clients or conferencing capture behavior.

## History and logs

**Disk logging is off by default.** Configure the global default under Terminal Behavior, or choose inherit/always save/do not save in an SSH configuration or tab menu.

Scrollback/saved history defaults to 50,000 lines and is adjustable. Default limits are 20 MiB per history file and 500 MiB total. Fast gzip compression is enabled by default; compression and disk work run in the background. Limits use compressed file size, retaining newer text and pruning the least recently updated records.

When enabled, history snapshots are saved every 30 seconds, on tab close and on application exit under `~/Library/Application Support/MyTerm/History/`. They are not unlimited logs or recordings. Cleared/evicted text cannot be recovered; full-screen programs contribute only their current screen. Crashes may lose unsaved snapshots.

**File → Session History** supports filtering, searching, exporting, deleting and clearing records older than 30 days or all records. Deleting an active session's record prevents its recreation during that connection. **Export Current Session Text** writes UTF-8 without ANSI controls or wide-character placeholders and works independently of automatic logging.

## Passwords and keys

SSH passwords are entered in the authentication dialog. With Remember after Successful Login selected, they are stored only after successful authentication, reused later, and replaced when rejected. Recognized prompts are scoped to connection definitions and host/user identity; custom prompts are one-time only. Key passphrases and verification codes are not saved automatically.

**Settings → SSH Passwords** supports names, session associations, updates, removal and clearing. Updates change only local records. Revealing a password requires a click; leaving the page or losing window focus hides it. Passwords do not enter terminal history, server JSON, process arguments or environment variables.

Credentials use app-managed SQLite with CryptoKit AES-256-GCM, without system Keychain access. Files are `passwords.sqlite` and `encryption.key` under `~/Library/Application Support/MyTerm/Credentials/`, with directory permissions 0700 and file permissions 0600. The key is local to support automatic login without a master password; a process able to read both files can decrypt them. Manual backups need both.

**Settings → SSH Keys** imports OpenSSH/PEM private keys, including encrypted formats, displays public keys and deletes managed copies. Authentication still depends on system OpenSSH, server algorithms and hardware key devices. Import preserves bytes and a matching `.pub`, without deleting originals or stripping passphrases. Keys live under `~/Library/Application Support/MyTerm/Keys/`; select them from the editor's key library or reference external files directly.

The key list shows explicit references from servers, saved sessions, active tabs and jump hosts. Deleting a referenced key requires extra confirmation. External programs and implicit references in SSH configuration are not counted.

## Configuration and backups

`servers.json`, `groups.json` and `sessions.json` under `~/Library/Application Support/MyTerm/` store servers, groups and saved tab collections. Group changes do not alter authentication or live connections. Invalid configuration originals are preserved; damaged group data can be repaired or removed through the recovery prompt.

- **Session configuration export/import:** versioned JSON for servers, groups and saved tab collections. Save active tabs first. Passwords, private-key files and history are excluded. Import does not connect; identical records are skipped, conflicts/invalid input cancel the import. Maximum file size: 20 MB.
- **OpenSSH export:** exports File-menu configurations for `ssh -F /path/to/config HostAlias`, including authentication, jumps, proxies and forwarding. Include references are retained. Keys, aliases and proxy helpers must be supplied on the destination Mac; this is not a self-contained backup.
- **Preferences backup/restore:** password-encrypted `.mytermbackup` includes servers, groups, saved sessions, active-tab configuration snapshots, appearance/language/terminal preferences, SSH passwords and managed keys. History, external SSH configuration/keys and installed fonts are excluded, as is the separate Codex proxy-password store.

Backups use a password-derived key and AES-256-GCM integrity protection. Lost backup passwords cannot be recovered. Restore validates first, then confirms configuration replacement and closes connections; failed writes attempt rollback. Managed-key paths adapt to the destination home directory. Restart after restoring to apply all preferences.

## Tests and source

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
