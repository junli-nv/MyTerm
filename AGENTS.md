# Project workflow

- Use `/bin/bash` for shell commands. Prefer `/Users/junliz/.venvs/codex-py314/bin/python` for Python, except where a project test environment is required.
- User requirement: installed and development applications must have consistent behavior. Do not treat a successful development build as sufficient release validation.
- User preference: after completing functional changes, update the local installer as part of delivery.
- Before delivering an installer, run `scripts/package-release.sh` and `scripts/create-dmg.sh`. These require the same window checks in Debug, Release and an app copied from the actual DMG, plus full bundle-content comparison.
- When asked to install, quit MyTerm, install from the validated DMG into `/Applications/MyTerm.app`, verify it with `scripts/verify-app-copy.py` and `scripts/window-controls-check.py`, and open that exact installed path. Do not rebuild or substitute `dist/MyTerm.app` during installation.
- Keep `dist/MyTerm.app` identical to the validated release bundle after packaging. Confirm the running executable path and version when reopening an installed release.
- Retain only the current local release package after successful validation and installation, as requested by the user. Preserve user settings and sessions during upgrades.

- For settings/localization changes, validate the complete settings window, not only an isolated page: switch languages repeatedly, preserve the selected page, and click all six visible tabs. Keep explicit tabs; do not reintroduce an adaptive overflow menu.

- Configuration forms must remain scrollable at their minimum supported window size, with long labels and explanations wrapping rather than clipping. Keep the SSH editor as a resizable standalone window with maximize/restore and a visible vertical scrollbar. Validate expanded jump, proxy and forwarding sections in Chinese and English in Debug, Release and the installed bundle.

- GitHub release retention: after publishing and verifying a new release, retain only v1.5.2 and the latest release. Delete other GitHub releases and their assets; preserve historical changelogs and source tags.
