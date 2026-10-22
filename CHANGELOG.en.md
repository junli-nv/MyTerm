# MyTerm release history


[简体中文](CHANGELOG.md) · English

These English summaries cover the archived release notes; they are not full translations. Each entry links to the original detailed record, which may be Chinese or bilingual. Historical defaults, limitations and validation results apply only to that release. See the [current user guide](README.en.md) for present behavior. Source tags and these records remain available after old release binaries are removed.

<a id="version-3.3.5"></a>

# MyTerm 3.3.5

[Release notes / 更新说明](packaging/RELEASE-NOTES-3.3.5.md): Codex display configuration; SFTP and ZMODEM conflict handling with resume retained.

<a id="version-3.3.4"></a>

# MyTerm 3.3.4

- Revert the forced local scrolling override for embedded Codex normal buffers introduced in 3.3.3. Scroll routing again follows terminal mouse-reporting mode. Settings windows still follow the active desktop.
- Fix an application crash during queued SFTP file/directory drag downloads when an earlier failed task closed the connection and a later task accessed a closed pipe. Closing is idempotent and requests on closed clients return errors. Add failed-queue and reconnection regression checks.
- Random history jumps during continued Codex output remain a known issue; reverting the override does not establish that the issue is resolved.

[Release notes](packaging/RELEASE-NOTES-3.3.4.md).

<a id="version-3.3.3"></a>

# MyTerm 3.3.3

- Settings, Codex integration and SSH configuration windows move to the active desktop when opened instead of activating a window on another desktop.
- In embedded Codex tabs, MyTerm handles wheel/trackpad scrolling in the normal terminal buffer even when the process enables mouse reporting. Output continues while reading history; scrolling back to the bottom resumes following. Alternate-screen applications retain their mouse routing. History remains subject to line and memory limits.
- Known issue: scrolling through history while Codex continues producing output can still jump unexpectedly to much earlier content. User testing confirmed that this change does not resolve the issue; further investigation is pending.

[Release notes](packaging/RELEASE-NOTES-3.3.3.md).

<a id="version-3.3.2"></a>

# MyTerm 3.3.2

- OpenSSH export aliases for sessions sharing a host now use myterm-session-name-short-id, distinguishing direct login entries from shared jumps. Collision protection remains; names without ASCII characters fall back to the host, with full names retained in comments.

[Release notes](packaging/RELEASE-NOTES-3.3.2.md).

<a id="version-3.3.1"></a>

# MyTerm 3.3.1

- Jump Host Manager adds password entry and show/hide; blank preserves credentials, and tests can use drafts without saving.

- OpenSSH export deduplicates jump hosts by effective connection settings, uses readable aliases with names and short identifiers, and lists referencing sessions. Multi-hop order is preserved; different proxy, authentication, compression or logging settings remain separate.

[Release notes](packaging/RELEASE-NOTES-3.3.1.md).

<a id="version-3.3"></a>

# MyTerm 3.3

- SFTP uploads offer overwrite, skip and apply-to-all conflict choices across recursive batches. File conflicts and recoverable operation errors no longer disconnect SFTP. Existing contents are preserved until replacement uploads finish.

[Release notes](packaging/RELEASE-NOTES-3.3.md).

<a id="version-3.2.13"></a>

# MyTerm 3.2.13

- Jump hosts support custom names in Settings → Jump Host Manager and the SSH editor. Empty names fall back to the host address. Lists and selection menus show names, and search includes names. Names persist through shared references, session import/export and backups; renaming does not change connections or password identifiers.

[Release notes](packaging/RELEASE-NOTES-3.2.13.md).

<a id="version-3.2.12"></a>

# MyTerm 3.2.12

- Move jump host management into the Settings sidebar; the SSH editor shortcut opens that same page.
- Test jump-host SSH connectivity and authentication without remote commands, fixing false failures on Windows and exec-restricted hosts. Reuse saved passwords and place testing above the session reference list.

[Release notes](packaging/RELEASE-NOTES-3.2.12.md).

<a id="version-3.2.11"></a>

# MyTerm 3.2.11

- Add independent management for all jump hosts: CRUD, reference protection, session selection, import/export and backup; test real SSH directly or through preceding hops, with failure details and cancellation.
- Merge SSH configuration checking and OpenSSH export into one window; keep the report open when the file picker is cancelled.

[Release notes](packaging/RELEASE-NOTES-3.2.11.md).

<a id="version-3.2.10"></a>

# MyTerm 3.2.10

- Add an SSH configuration inventory linking sessions, jumps, snapshots and open tabs with password metadata, explicit key-file checks and unreferenced credentials. Preview dependencies before OpenSSH export without reading secrets or deleting records.

[Release notes](packaging/RELEASE-NOTES-3.2.10.md).

<a id="version-3.2.9"></a>

# MyTerm 3.2.9

- Add shared jump profiles with backed-up legacy migration, synchronized references, independent copies and impact confirmation. Destination and jump password drafts can be shown or hidden.

[Release notes](packaging/RELEASE-NOTES-3.2.9.md).

<a id="version-3.2.8"></a>

# MyTerm 3.2.8

- Allow OpenSSH export of sessions sharing a host by generating distinct, stable aliases while preserving explicit connection settings and leaving saved sessions unchanged.

[Release notes](packaging/RELEASE-NOTES-3.2.8.md).

<a id="version-3.2.7"></a>

# MyTerm 3.2.7

- Fix the partially filled status bar after SSH disconnection. The background fills its pane, controls span wide windows, and narrow split panes scroll horizontally.

[Release notes](packaging/RELEASE-NOTES-3.2.7.md).

<a id="version-3.2.6"></a>

# MyTerm 3.2.6

- Fill the Codex execution bar with a consistent background: status left, authorization controls in the middle, settings right, with narrow-pane scrolling.
- Resume Codex conversations through the native picker while binding the current SSH UUID and fresh authorization; reject stale UUIDs with rediscovery guidance.

[Release notes](packaging/RELEASE-NOTES-3.2.6.md).

<a id="version-3.2.5"></a>

# MyTerm 3.2.5

- Keep Codex SSH launch settings in the session chooser, preserving saved values and removing the duplicate access-page form.
- Enlarge the launch form and keep Cancel and Confirm and launch outside its scrolling content.

[Release notes](packaging/RELEASE-NOTES-3.2.5.md).

<a id="version-3.2.4"></a>

# MyTerm 3.2.4

- Add opt-in terminal diagnostics with bounded in-memory captures, incident markers, and metadata-only ZIP export; no terminal text or credentials are collected.
- Resume output following when input resumes after selection, even if the caret remains visible.
- Clear stale composition state that could affect enhanced Enter encoding; the reported ordinary-English double-Enter issue remains unconfirmed.

[Release notes](packaging/RELEASE-NOTES-3.2.4.md).

<a id="version-3.2.3"></a>

# MyTerm 3.2.3

- Configurable Codex SSH command length, timeout, output capacity and default approval mode, retaining initial defaults.
- Saved launch defaults and per-tab execution settings; renewal retains that tab’s choices.
- A single control row replaces expandable history and the permanent Stop button; active/queued commands remain cancellable.
- MCP reports incomplete-output reasons and supports larger command transport and output paging beyond 1 MiB.


[Release notes](packaging/RELEASE-NOTES-3.2.3.md).

<a id="version-3.2.2"></a>

# MyTerm 3.2.2

Add command broadcasting to selected panes in the current tab: explicit targets, shell-readiness confirmation, single-line submission, connection revalidation and pane markers. Codex tabs are excluded; input is never replayed after reconnection. Add Check for Updates: after confirmation, download from GitHub, validate, replace and restart, retaining or restoring the previous app on installation errors. [Release notes](packaging/RELEASE-NOTES-3.2.2.md).

<a id="version-3.2.1"></a>

# MyTerm 3.2.1

Fix mixed split sizing: new splits halve only the selected region and preserve existing divider proportions, including manual adjustments. [Release notes](packaging/RELEASE-NOTES-3.2.1.md).

<a id="version-3.2"></a>

# MyTerm 3.2

Add top/bottom and left/right splits within tabs, adjustable dividers, moving existing sessions and detaching panes. Defaults are ⌘⇧H / ⌘⇧V, customizable in Terminal Behavior. Panes retain independent sessions, SFTP and Codex authorization. Saved sessions preserve layout and selection, but not divider proportions. History remains available in menus and the sidebar. [Release notes](packaging/RELEASE-NOTES-3.2.md).

<a id="version-3.1.14"></a>

# MyTerm 3.1.14

Choose SSH authentication before entering credentials. Password and private-key inputs are mutually exclusive; Automatic uses existing configuration. Switching modes preserves credentials, and password mode no longer passes a private-key file. [Release notes](packaging/RELEASE-NOTES-3.1.14.md).

<a id="version-3.1.13"></a>

# MyTerm 3.1.13

Add an optional destination password to SSH configuration. Blank retains the saved password; secrets use the local encrypted store and stay out of session configuration. Unify credential matching across ordinary password prompts, preserving legacy migration and replacement after rejection. [Release notes](packaging/RELEASE-NOTES-3.1.13.md).

<a id="version-3.1.12"></a>

# MyTerm 3.1.12

Default the Codex executable to `/opt/homebrew/bin/codex`, preserving saved custom paths. Fix stale Chinese labels in SSH approval/execution controls after language changes. Link the About window to the MyTerm repository. [Release notes](packaging/RELEASE-NOTES-3.1.12.md).

<a id="version-3.1.11"></a>

# MyTerm 3.1.11

Give each forwarding rule a separate Remove forwarding text button instead of the small minus icon beside the type picker. Add removal, empty-list persistence, reload and re-add checks. [Release notes](packaging/RELEASE-NOTES-3.1.11.md).

<a id="version-3.1.10"></a>

# MyTerm 3.1.10

Fix tab titles failing to refresh after renaming, with matching tab width updates. Right-click or Control-click selects the target tab before opening its menu; remove the redundant Select Session item. [Release notes](packaging/RELEASE-NOTES-3.1.10.md).

<a id="version-3.1.9"></a>

# MyTerm 3.1.9

Fix tab context menus for trackpad presses delivered as primary-typed events with the secondary button number. Duplicate events from one press do not reopen the menu. Preserve single-click selection and terminal focus, tab dragging, and double-clicking blank title-bar space to maximize. [Release notes](packaging/RELEASE-NOTES-3.1.9.md).

<a id="version-3.1.8"></a>

# MyTerm 3.1.8

Unify native tab click, drag and menu handling across the full strip height; add complete press/release and edge-hit checks. [Release notes](packaging/RELEASE-NOTES-3.1.8.md).

<a id="version-3.1.7"></a>

# MyTerm 3.1.7

Multiple Codex tabs can independently authorize access to one SSH connection, with serialized commands; usage and testing documentation updated.

Fix tab context menus requiring a double-click before opening. [Release notes](packaging/RELEASE-NOTES-3.1.7.md).

<a id="version-3.1.6"></a>

# MyTerm 3.1.6

Restore held-letter repeats for Vim navigation instead of the English-input accent menu. [Release notes](packaging/RELEASE-NOTES-3.1.6.md).

<a id="version-3.1.5"></a>

# MyTerm 3.1.5

Add standard, fast and page navigation modes for full-screen trackpad scrolling. [Release notes](packaging/RELEASE-NOTES-3.1.5.md).

<a id="version-3.1.4"></a>

# MyTerm 3.1.4

Preconfigure and share jump passwords across sessions, and select saved multi-hop routes. [Release notes](packaging/RELEASE-NOTES-3.1.4.md).

<a id="version-3.1.3"></a>

# MyTerm 3.1.3

Launch standalone local Codex in a chosen directory, without Bash association or MyTerm MCP. [Release notes](packaging/RELEASE-NOTES-3.1.3.md).

<a id="version-3.1.2"></a>

# MyTerm 3.1.2

Add local Bash integration with shared Codex proxy settings and independent SSH execution authorization. [Release notes](packaging/RELEASE-NOTES-3.1.2.md).

<a id="version-3.1.1"></a>

## MyTerm 3.1.1

Support multiline Codex SSH scripts while retaining whole-script approval and output limits. [Release notes](packaging/RELEASE-NOTES-3.1.1.md).

<a id="version-3.1"></a>

## MyTerm 3.1

Vertical navigation in settings and Codex Integration, resizable window, dark/light palette previews and simplified font selection. [Release notes](packaging/RELEASE-NOTES-3.1.md).

<a id="version-3.0.3"></a>

## MyTerm 3.0.3

Preserve password associations across SSH configuration edits; migrate legacy credentials and verify key configuration retention. [Release notes](packaging/RELEASE-NOTES-3.0.3.md).

<a id="version-3.0.2"></a>

## MyTerm 3.0.2

Fix live language switching for system commands in Edit and Window without restarting. See [release notes](packaging/RELEASE-NOTES-3.0.2.md).

<a id="version-3.0.1"></a>

## MyTerm 3.0.1

Fix chooser localization; default to execution with per-command approval; remove duplicate plan capture and session-ID copying. Revoke last-owner access and roll back failed startup authorization. See [release notes](packaging/RELEASE-NOTES-3.0.1.md).

<a id="version-3.0"></a>

## MyTerm 3.0

Drain and release exited PTYs, clean closed-session history metadata, add a configurable shared scrollback memory budget, and make initial Codex history analysis opt-in, and remove continuous monitoring. See [release notes](packaging/RELEASE-NOTES-3.0.md).

<a id="version-2.0"></a>

## MyTerm 2.0

Cross-module regression review; fixes stalled malformed-UTF-8 output pagination and delayed small command-output reads. Rejects special SFTP target/resume files before blocking reads. Adds a unified test runner with explicit build/app selection, real XQuartz forwarding checks and bilingual current documentation.

[Full bilingual release notes](packaging/RELEASE-NOTES-2.0.md) · [Validation scope](docs/TESTING.en.md)

<a id="version-1.6.17"></a>

## MyTerm 1.6.17

Restored the top-right SFTP entry during asynchronous SSH initialization, brought detached panels to the front, and added stable-toolbar regression checks.

[Original release notes](packaging/RELEASE-NOTES-1.6.17.md)

<a id="version-1.6.16"></a>

## MyTerm 1.6.16

Added SFTP disconnect, native multi-selection, batch transfers, Finder drag-and-drop, recursive directory transfers and a detachable panel; removed SCP. Installation distinguishes GUI processes from externally owned MCP adapters.

[Original release notes](packaging/RELEASE-NOTES-1.6.16.md)

<a id="version-1.6.15"></a>

## MyTerm 1.6.15

Introduced a two-level group/session tree and creation of a group by dropping one ungrouped session onto another.

[Original release notes](packaging/RELEASE-NOTES-1.6.15.md)

<a id="version-1.6.14"></a>

## MyTerm 1.6.14

Added drag-to-reorder for SSH, local shell and Codex tabs while preserving connections, output and selected-tab identity.

[Original release notes](packaging/RELEASE-NOTES-1.6.14.md)

<a id="version-1.6.13"></a>

## MyTerm 1.6.13

Returned the active approval mode through MCP and added Copy Session ID to SSH tab context menus.

[Original release notes](packaging/RELEASE-NOTES-1.6.13.md)

<a id="version-1.6.12"></a>

## MyTerm 1.6.12

Added switchable per-command approval and allow-for-this-session modes, still bounded by grants and output-completeness checks.

[Original release notes](packaging/RELEASE-NOTES-1.6.12.md)

<a id="version-1.6.11"></a>

## MyTerm 1.6.11

Separated Codex configuration from SSH integration, displayed independent login/proxy check results, and validated startup dependencies.

[Original release notes](packaging/RELEASE-NOTES-1.6.11.md)

<a id="version-1.6.10"></a>

## MyTerm 1.6.10

Lowered the minimum font size to 5 pt and made the key after the default tmux Ctrl+B prefix use the ASCII keyboard layout.

[Original release notes](packaging/RELEASE-NOTES-1.6.10.md)

<a id="version-1.6.9"></a>

## MyTerm 1.6.9

Reduced execution-control refresh overhead with change-based updates, lightweight polling, lazy history layout and idle timer shutdown.

[Original release notes](packaging/RELEASE-NOTES-1.6.9.md)

<a id="version-1.6.8"></a>

## MyTerm 1.6.8

Made execution duration and command quotas configurable, defaulting to 60 minutes and 300 commands, and added in-tab grant renewal.

[Original release notes](packaging/RELEASE-NOTES-1.6.8.md)

<a id="version-1.6.7"></a>

## MyTerm 1.6.7

Allowed plans in read-only mode and renewed grants in existing tabs; compacted approval controls, made plans collapsible, and set StrictHostKeyChecking=no.

[Original release notes](packaging/RELEASE-NOTES-1.6.7.md)

<a id="version-1.6.6"></a>

## MyTerm 1.6.6

Displayed plans without a plan-approval prompt, required button approval for each command, and consolidated SSH selection at Codex startup.

[Original release notes](packaging/RELEASE-NOTES-1.6.6.md)

<a id="version-1.6.5"></a>

## MyTerm 1.6.5

Moved execution plans and command approval controls into the associated Codex tab, with expandable execution records.

[Original release notes](packaging/RELEASE-NOTES-1.6.5.md)

<a id="version-1.6.4"></a>

## MyTerm 1.6.4

Introduced explicit SSH command execution grants, separate execution channels, paged output and completeness checks. The original limits were 10 minutes and 30 commands; later versions changed them.

[Original release notes](packaging/RELEASE-NOTES-1.6.4.md)

<a id="version-1.6.3"></a>

## MyTerm 1.6.3

Fixed MCP executable path serialization, exposed external registration status, and added more specific startup failure diagnostics.

[Original release notes](packaging/RELEASE-NOTES-1.6.3.md)

<a id="version-1.6.2"></a>

## MyTerm 1.6.2

Reused saved Codex login credentials, continued analysis after login, and preserved output and exit codes when Codex ended.

[Original release notes](packaging/RELEASE-NOTES-1.6.2.md)

<a id="version-1.6.1"></a>

## MyTerm 1.6.1

Added SSH selection at Codex startup, opt-in continuous monitoring, configurable history ranges, and paged frozen snapshots.

[Original release notes](packaging/RELEASE-NOTES-1.6.1.md)

<a id="version-1.6"></a>

## MyTerm 1.6

Introduced opt-in read-only SSH output sharing with Codex, a local MCP adapter, and independent authenticated Codex proxy settings.

[Original release notes](packaging/RELEASE-NOTES-1.6.md)

<a id="version-1.5.2"></a>

## MyTerm 1.5.2

Fixed delayed asterisk echo while retaining fragmented ZMODEM handshake detection and transfer checks.

[Original release notes](packaging/RELEASE-NOTES-1.5.2.md)

<a id="version-1.5.1"></a>

## MyTerm 1.5.1

Displayed SSH key references, required additional confirmation for referenced keys, and rechecked references before deletion.

[Original release notes](packaging/RELEASE-NOTES-1.5.1.md)

<a id="version-1.5"></a>

## MyTerm 1.5

Added saved-password names, session references, and on-demand password visibility with automatic hiding.

[Original release notes](packaging/RELEASE-NOTES-1.5.md)

<a id="version-1.4.13"></a>

## MyTerm 1.4.13

Kept text selections usable during continuous output, paused automatic following while selecting history, and restored following afterward.

[Original release notes](packaging/RELEASE-NOTES-1.4.13.md)

<a id="version-1.4.12"></a>

## MyTerm 1.4.12

Preserved output after SSH disconnection and repaired R/r reconnect handling and terminal view stability.

[Original release notes](packaging/RELEASE-NOTES-1.4.12.md)

<a id="version-1.4.11"></a>

## MyTerm 1.4.11

Introduced two-stage selection: first double-click selects whitespace-delimited text; another double-click expands to the logical line.

[Original release notes](packaging/RELEASE-NOTES-1.4.11.md)

<a id="version-1.4.10"></a>

## MyTerm 1.4.10

Improved logical-line copying and selection across wrapping and font changes; double-click selected the logical line in this version.

[Original release notes](packaging/RELEASE-NOTES-1.4.10.md)

<a id="version-1.4.9"></a>

## MyTerm 1.4.9

Restored automatic joining of soft-wrapped lines by default, corrected stale wrap relationships, and retained optional screen-line copying.

[Original release notes](packaging/RELEASE-NOTES-1.4.9.md)

<a id="version-1.4.8"></a>

## MyTerm 1.4.8

Changed full-screen copying to preserve screen rows and added an explicit wrapped-line joining action. This behavior was revised in 1.4.9.

[Original release notes](packaging/RELEASE-NOTES-1.4.8.md)

<a id="version-1.4.7"></a>

## MyTerm 1.4.7

Made the SSH editor resizable with persistent scrolling and improved expanded forwarding, proxy and jump-host layouts.

[Original release notes](packaging/RELEASE-NOTES-1.4.7.md)

<a id="version-1.4.6"></a>

## MyTerm 1.4.6

Added per-session logging overrides while retaining global limits and background gzip compression.

[Original release notes](packaging/RELEASE-NOTES-1.4.6.md)

<a id="version-1.4.5"></a>

## MyTerm 1.4.5

Disabled automatic disk logs by default; added history line, file-size and total-capacity limits and history cleanup.

[Original release notes](packaging/RELEASE-NOTES-1.4.5.md)

<a id="version-1.4.4"></a>

## MyTerm 1.4.4

Disabled outer SSH escape processing so remote console sequences such as ~. reach the remote application.

[Original release notes](packaging/RELEASE-NOTES-1.4.4.md)

<a id="version-1.4.3"></a>

## MyTerm 1.4.3

Moved the SFTP toggle beside the new-tab button and kept toolbar geometry stable between local and SSH tabs.

[Original release notes](packaging/RELEASE-NOTES-1.4.3.md)

<a id="version-1.4.2"></a>

## MyTerm 1.4.2

Kept all six settings tabs visible, preserved the selected page on language changes, and added full-window localization checks.

[Original release notes](packaging/RELEASE-NOTES-1.4.2.md)

<a id="version-1.4.1"></a>

## MyTerm 1.4.1

Improved theme and font layout, wrapping, alignment, and scrolling in both interface languages.

[Original release notes](packaging/RELEASE-NOTES-1.4.1.md)

<a id="version-1.4"></a>

## MyTerm 1.4

Expanded ANSI and text colors, HEX editing, theme presets, .itermcolors import/export, and background opacity.

[Original release notes](packaging/RELEASE-NOTES-1.4.md)

<a id="version-1.3"></a>

## MyTerm 1.3

Added terminal side padding and configurable keyword highlighting while preserving copied and transferred content.

[Original release notes](packaging/RELEASE-NOTES-1.3.md)

<a id="version-1.2.1"></a>

## MyTerm 1.2.1

Fixed toolbar hit testing and window dragging; added a direct SFTP toggle and matching Debug/Release interaction checks.

[Original release notes](packaging/RELEASE-NOTES-1.2.1.md)

<a id="version-1.2"></a>

## MyTerm 1.2

Compact combined title/tab bar, hidden status bar by default, keyboard tab cycling, and double-click maximize/restore.

[Original release notes](packaging/RELEASE-NOTES-1.2.md)

<a id="version-1.1"></a>

## MyTerm 1.1

Bundled trzsz client for terminal file and directory transfers, including tmux workflows and configurable drag-and-drop protocol selection.

[Original release notes](packaging/RELEASE-NOTES-1.1.md)

<a id="version-1.0"></a>

## MyTerm 1.0

Application icon and About window; improved group editing and drag-and-drop; optional SSH debugging; ordered jump hosts with individual authentication settings.

[Original release notes](packaging/RELEASE-NOTES-1.0.md)
