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

<a id="codex-helper-permissions"></a>

## First-run verification after installing or updating Codex

Besides its main executable, Codex may launch its own helpers, such as `codex-code-mode-host` (use the name in the actual package and system prompt). This belongs to Codex, not MyTerm's `--myterm-mcp` process. The [OpenAI App Server documentation](https://learn.chatgpt.com/docs/app-server) describes starting a local Code Mode host by default. A blocked helper has been reported to cause tool discovery failure, but `host exited during handshake` alone does not establish a permission issue in every case.

You can complete first-run verification and any necessary approval beforehand. MyTerm cannot pre-authorize all external programs or future versions on your behalf. The app does not automatically perform the Codex-helper verification below.

1. Install the complete Codex package from a trusted source and confirm its CLI path in MyTerm's Codex Configuration. Do not copy only the main executable or mix helpers from different versions. Configure MyTerm's independent Codex proxy first if needed.
2. Sign in through MyTerm and actually start a new SSH-analysis Codex tab. Select a test SSH session, uncheck Allow SSH command execution and Read existing output when connecting, and enter: “Only discover MyTerm MCP tools and confirm the associated SSH session. Do not read terminal output or execute SSH commands.” This exercises the real integration and may consume normal Codex usage. Running `codex --version`, checking login or starting a Local Work tab is not a substitute for this SSH integration test.
3. If macOS names a Codex helper in a prompt, record the exact name and message. For an unidentified-developer / cannot-check-for-malicious-software warning, verify the installation source, then follow [Apple's instructions](https://support.apple.com/en-us/102445): after attempting to launch, open System Settings → Privacy & Security → Security → Open Anyway and confirm Open. Handle folder or local-network prompts under their corresponding permissions. Do not blindly apply these steps to damaged-file or malware warnings. Managed Macs may require IT assistance.
4. After approval, close the failed Codex tab, start a new one and repeat the tool-discovery test. Success means Codex actually discovers MyTerm tools and confirms the selected session, not just a successful login or a passing MyTerm check.
5. If it still fails, start a new recording in Help → Terminal Diagnostics, reproduce and export the archive. Include the incident time, exact system prompt and blocked program name, Codex version and MCP check result, but no login codes, tokens or passwords. MyTerm logs may not capture a Codex helper failing before tool calls begin, so provide the system prompt separately.

macOS normally retains an exception for the same software, so approval is not needed on every launch. However, a Codex update, replaced helper, changed installation path or host, or organizational policy change may require verification again. Updating MyTerm alone does not necessarily require re-authorizing unchanged Codex software. Run this test after installing or updating Codex to catch problems before troubleshooting real machines. Stable signing and notarization are responsibilities of the respective software distributor; signing MyTerm does not sign or authorize Codex helpers.

MyTerm's Check SSH MCP interface directly launches the MyTerm MCP process and checks `initialize` / `tools/list`; it does not launch Codex's Code Mode host. A pass therefore does not guarantee that Codex's own helpers can run. Relaxing SSH command approval, granting Full Disk Access or disabling Gatekeeper is not a general solution.

## How to check

Use Codex configuration → SSH MCP interface → Check SSH MCP interface to check actual helper startup and MCP initialization/tool discovery. Permission errors appear only when launch is actually denied. Quarantine, signature and Gatekeeper assessments are retained only in the diagnostic archive, not displayed in MCP status or used to decide whether the interface passes. Checks are read-only, do not change system policy, do not request all permissions and do not read SSH output or execute commands.

A valid signature establishes bundle integrity, not Developer ID signing or Apple notarization. A failed Gatekeeper assessment does not prove that this launch was blocked: a user may already have allowed an ad-hoc app. An actual launch error such as `permission_denied`, or the matching system prompt, provides evidence of a permission denial. Absence of a quarantine flag does not establish that all permissions are granted.

After checking, export Help → Terminal Diagnostics. Its `mcpSecurity` field contains the assessment time, boolean observations and tool exit codes; an absent or `null` field means no check has run since this app launch. A security tool exit code of `null` means it failed to launch or timed out, never a pass. No raw system output, user paths or credentials are captured. For MCP lifecycle events, start a new recording before launching the affected Codex tab.

macOS has no public interface for this app to enumerate every TCC permission. These checks do not determine permission on another machine, in another Codex/IDE host or for every protected folder. If it still fails, provide the incident time, exact system prompt including the blocked program name, check results, and whether the app was updated or another copy launched. Checking this app does not prove external Codex uses the same executable path.

Apple recommends an Apple-issued signing identity so macOS local network privacy can reliably identify a program. Ad-hoc signing and updates are factors to investigate, not proof of this incident's root cause.

References: [Safely open apps](https://support.apple.com/en-us/102445), [File access protection](https://support.apple.com/en-ca/guide/security/secddd1d86a6/web), [Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

Diagnostic archives include `诊断摘要.txt` (Chinese) and `Diagnostic-Summary.en.txt` (English). Read these first for observed stages, impact, next steps and limits of the evidence. `diagnostic.json` retains raw codes and the timestamped `mcpHealth` check result. The Codex interface check also displays a readable explanation, with numeric details collapsed. A normal EOF or a failed Gatekeeper assessment alone is not classified as a root cause. Explicit checks and captured helper events are described separately; missing events are not proof of success. Summaries use fixed local rules, not a model, and contain no terminal text or credentials.
