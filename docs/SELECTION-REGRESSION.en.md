# Terminal interaction regression matrix

[简体中文](SELECTION-REGRESSION.md) · English · [Full regression guide](TESTING.en.md)

This is a coverage inventory, not a claim that every combination has passed. Check the logs for the exact app/configuration tested. The complete suite runs in `window-controls-check.py`, including Debug, Release and the actual DMG copy during packaging. `--smoke-test --window-controls-check --terminal-copy-only` selects the focused clipboard checks. Checks save and restore the clipboard; preference fixtures use isolated defaults.

| Interaction / option | Automated evidence | Remaining boundary |
| --- | --- | --- |
| First double-click token, repeat double-click logical row, rapid quadruple click | `TerminalCopyCheck`: normal/alternate buffers, punctuation/URLs, CJK, each wrapped row | Physical click timing/device differences |
| tmux copy-mode page up twice, page down, scroll up/down → first/repeat double-click → copy/row drag across records | `TerminalSelectionCheck` replays isolated real tmux output; asserts token, entire record, clipboard, screen-row copy and unchanged buffer | User tmux configuration, nested panes, tmux versions and physical keys/trackpad |
| Native soft wraps (including blank/wide edges), coordinate-repainted wide edge gaps, hard breaks, stale wraps, exact-width hard lines | `TerminalCopyCheck`: exact clipboard and row-selection checks | Coordinate redraws cannot distinguish every exact-width hard break from a soft wrap |
| Coordinate-painted short lines, pane/table borders, styled status | `TerminalSelectionCheck`: must not join independent rows | Borderless panes and identical styles remain ambiguous; fallback only applies to explicit token/logical-row selection |
| 22 rendered separators: ASCII space/HT, Unicode spacing characters (including no-break/Ogham/figure/en/em/thin/hair/mathematical/ideographic spaces), blank Braille and Hangul fillers | `TerminalSelectionCheck`: rendered left/right tokens, blank cells and wide continuation cells | Font-dependent glyph appearances; invisible formatting controls are not automatically separators |
| CJK, wide characters, emoji joiners/graphemes | `TerminalCopyCheck`, `TerminalSelectionCheck` | Every Unicode/font/combining sequence is not enumerated |
| Remote mouse ownership / Shift local override | `TerminalCopyCheck`, `TerminalPasteCheck` | Every remote TUI's mouse protocol |
| Auto-copy on/off, right-click paste on/off, Shift menu, persistence | `MouseInteractionCheck`, `TerminalPasteCheck`; shared Release/DMG checks, formerly partly Debug-only | Physical app switching / first-event delivery |
| Disable terminal bell | `MouseInteractionCheck`: default and preference reload | Audible output remains a manual device/system-volume check |
| Selection while output continues; resume following | `TerminalCopyCheck`, `TerminalScrollCheck` | Long-running workloads and OS event scheduling |
| tmux/less page/search/resize repaint → copy | `TerminalCopyCheck` captured real tmux/less stream, independent text oracle | Every pager/configuration |
| Font zoom/reflow and Ctrl-wheel | `TerminalCopyCheck`, `FontZoomKeyboardCheck`, `MouseInteractionCheck` | Display scaling and physical gesture behavior |
| Standard/Fast/Page scrolling, reversal/momentum; Codex isolation | `FullscreenScrollCheck`, `TerminalScrollCheck` | Physical device acceleration |
| Codex CSI 3J replay while reading/scrolling, timeout and transparency | `CodexReplayCheck` | Real CLI/model workloads and physical trackpad acceptance |
| Fonts/themes/history persistence and group dialog/drop | `AppearanceHistoryCheck`, `GroupNameDialogCheck`; shared Release/DMG checks, formerly Debug-only | Platform/font availability |

## Retaining the reproduction

`python3 scripts/capture-tmux-copy-fixture.py --swift Sources/MyTerm/TmuxCopyModeFixture.swift` uses a private tmux server and synthetic records. It captures incremental terminal bytes; the text oracle uses the known original records and tmux's copy-mode scroll offset, independently of MyTerm's parser. It must never capture a user's existing pane or private output. Replaying the same test on the preceding implementation must fail, while the fixed implementation must pass. Do not replace this with an assertion that the text merely appears on screen.

The fallback never changes buffer wrap flags or incoming bytes. Ordinary drag selection and built-in Codex scrolling stay outside it. Full-screen rows can lack enough information for exact reconstruction; preserve screen-line copy and record those limits rather than declaring exhaustive coverage.
