# MyTerm release history

[简体中文](CHANGELOG.md) · English

These English summaries cover the archived release notes; they are not full translations. Each entry links to the original detailed record, which may be Chinese or bilingual. Historical defaults, limitations and validation results apply only to that release. See the [current user guide](README.en.md) for present behavior. Source tags and these records remain available after old release binaries are removed.

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
