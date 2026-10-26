# macOS permissions and security checks

[简体中文](PERMISSIONS.md) · English

MyTerm does not require granting every permission. macOS prompts, MyTerm SSH command approval and Codex tool approval are separate mechanisms.

| Item | When it applies / where to check |
| --- | --- |
| Permission to run (Gatekeeper) | Current releases are ad-hoc signed and not notarized. After downloading, you may need System Settings → Privacy & Security → Security → Open Anyway. This permits the app to run; it does not authorize SSH commands. Install in Applications before running. |
| Files and Folders | Uploads, downloads, imports, exports or local shell/Codex work accessing protected Desktop, Documents, Downloads, removable disks or network volumes may prompt for access. Grant only locations needed for the task; check Privacy & Security → Files and Folders. |
| Local Network | LAN SSH/SFTP connections or LAN proxies may prompt for local network access. Check the relevant app in Privacy & Security → Local Network. Internet proxy or Codex login success does not prove LAN access works. |
| Automation | Normal terminal use and SSH MCP handshakes do not depend on controlling other apps. AppleScript commands, external tools or development installation scripts may request control of a target app. Check the actual sender and target. `scripts/install-release.sh` uses AppleScript to quit old MyTerm and may request Automation permission for the script's host. |
| Accessibility and Input Monitoring | Normal typing, in-app shortcuts, selection/copy and SSH MCP do not require either. Input monitors in the code are local to this app; do not grant these blindly to fix MCP handshakes. External automation tools or user-run commands can have separate requirements. |
| Screen Recording, Microphone and Camera | MyTerm terminal and SSH MCP features do not require these. Teams screen sharing or other tools have their own permission requirements. |
| Full Disk Access | Not a normal prerequisite for MyTerm or MCP. Assess separately only when a user-directed local task requires additional protected data. MyTerm does not automatically request it or recommend it as a generic fix. |
| Administrator / remote permissions | Write access to replace an app in `/Applications`, local `sudo` and permissions of remote SSH accounts are separate. MyTerm's Allow SSH command execution does not grant macOS administrator privileges. |

SSH MCP uses stdio and a local Unix socket, not screen capture or Accessibility to read a terminal. Do not enable screen recording/full disk access or reset all privacy permissions to try to fix a handshake.

## How to check

Use Codex configuration → SSH MCP interface → Check SSH MCP interface to check actual helper startup and MCP initialization/tool discovery. Permission errors appear only when launch is actually denied. Quarantine, signature and Gatekeeper assessments are retained only in the diagnostic archive, not displayed in MCP status or used to decide whether the interface passes. Checks are read-only, do not change system policy, do not request all permissions and do not read SSH output or execute commands.

A valid signature establishes bundle integrity, not Developer ID signing or Apple notarization. A failed Gatekeeper assessment does not prove that this launch was blocked: a user may already have allowed an ad-hoc app. An actual launch error such as `permission_denied`, or the matching system prompt, provides evidence of a permission denial. Absence of a quarantine flag does not establish that all permissions are granted.

After checking, export Help → Terminal Diagnostics. Its `mcpSecurity` field contains the assessment time, boolean observations and tool exit codes; an absent or `null` field means no check has run since this app launch. A security tool exit code of `null` means it failed to launch or timed out, never a pass. No raw system output, user paths or credentials are captured. For MCP lifecycle events, start a new recording before launching the affected Codex tab.

macOS has no public interface for this app to enumerate every TCC permission. These checks do not determine permission on another machine, in another Codex/IDE host or for every protected folder. If it still fails, provide the incident time, exact system prompt including the blocked program name, check results, and whether the app was updated or another copy launched. Checking this app does not prove external Codex uses the same executable path.

Apple recommends an Apple-issued signing identity so macOS local network privacy can reliably identify a program. Ad-hoc signing and updates are factors to investigate, not proof of this incident's root cause.

References: [Safely open apps](https://support.apple.com/en-us/102445), [File access protection](https://support.apple.com/en-ca/guide/security/secddd1d86a6/web), [Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

Diagnostic archives include `诊断摘要.txt` (Chinese) and `Diagnostic-Summary.en.txt` (English). Read these first for observed stages, impact, next steps and limits of the evidence. `diagnostic.json` retains raw codes and the timestamped `mcpHealth` check result. The Codex interface check also displays a readable explanation, with numeric details collapsed. A normal EOF or a failed Gatekeeper assessment alone is not classified as a root cause. Explicit checks and captured helper events are described separately; missing events are not proof of success. Summaries use fixed local rules, not a model, and contain no terminal text or credentials.
