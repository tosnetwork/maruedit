# Hidemaru Chrome Parity Matrix

Baseline: Hidemaru Editor 9.57 official help, compared with MaruEdit `main`.
This matrix covers application chrome only: menus, command toolbar, function-key
strip, and status bar. Windows-only shell integrations use a native macOS
equivalent and must never be reported as byte-for-byte parity.

Status legend:

- ✅ **Complete** — the compatible behavior is implemented and has direct test evidence.
- 🟡 **Partial / native substitute** — useful coverage exists, but behavior, scope, or
  verification is not yet equivalent.
- ❌ **Incomplete** — a confirmed compatible Hidemaru capability is absent or an
  acceptance requirement is not met.

Overall status: **not yet 100% aligned**. This matrix deliberately distinguishes
passing MaruEdit regression tests from exhaustive Hidemaru feature parity.

| Area | ✅ Complete | 🟡 Partial/native | ❌ Incomplete |
|---|---:|---:|---:|
| Menu rows | 1 | 7 | 5 |
| Toolbar/function-key rows | 9 | 3 | 0 |
| Status-bar rows | 16 | 0 | 0 |
| Acceptance gates | 1 | 2 | 2 |

## Menu bar

Hidemaru's documented top-level business menus are File, Edit, Convert,
View, Insert, Search, Highlight, Bookmark, Tools, Window, Macro, Other, and
Help. macOS additionally requires the application menu; MaruEdit keeps that
native menu before the Hidemaru-compatible business menus.

| Hidemaru menu | MaruEdit today | Status | Remaining gap |
|---|---|---|---|
| File | Reload, properties, rename, View Mode, append save/read, bounded partial open, editable hexadecimal binary mode, save/close variants, recent projects, and workspace history | 🟡 Partial | Build an official File-command inventory and verify every encoding, history, desktop/workspace, and platform-specific entry one by one. |
| Edit | Undo/clipboard, line editing, histories, quoted clipboard, deletion restore, selections, Caps Lock correction, and native IME reconversion | ❌ Incomplete | Add repeat-last-operation, append cut/copy, delete-before/after-cursor variants, invert selection, multi-selection reservation, BOX paste, and paste-with-history variants. Physical Caps Lock remains macOS-owned. |
| Convert | Case, generic half/full-width, hiragana/katakana, and Tab/space conversions | ❌ Incomplete | Add alphanumeric/symbol/space-only width conversion, katakana-only width conversion, conversion dialogs, and extensible conversion-module behavior. |
| View | Wrapping, invisibles, ruler marks, profile tab stops, editable vertical writing, continuous column flow, splits, chrome visibility, and output-pane focus | 🟡 Partial | Complete the official view/frame inventory and native mappings; browser/file-manager frame variants and all display configuration have not been audited one by one. |
| Insert | Date/time, page break, C0/DEL control codes, and encoding-aware file-content insertion | 🟡 Partial | The implemented subset is tested, but the official insertion-command inventory has not been exhaustively mapped. |
| Search | Search/replace/grep, case/word/regex/fuzzy flags, return to search start, edit marks, all-match operations, and persistent ranges | 🟡 Partial | Map and implement the remaining fine-grained Hidemaru search, marker, candidate, and result commands. |
| Highlight | Red/yellow/blue markers, navigation, clearing, and sorted highlight list with preview/jump/remove | 🟡 Partial | Add the remaining temporary color-marker operations, including individual removal and complete select/navigation variants. |
| Bookmark | Toggle, previous/next, clear, and a document list with jump/remove | ✅ Complete | No confirmed compatible gap in the scoped bookmark row; retain official-command regression coverage. |
| Tools | Compare/difference, tag navigation, dynamic external commands, and command-list access | ❌ Incomplete | Add tags-file generation and finish the official Tools-command mapping. |
| Window | Tab list, close-other/left/right, pane focus, tab cycling, native Minimize/Zoom, and session restoration | 🟡 Native substitute | Windows arrangement/process/desktop behavior is not identical; document each native replacement explicitly. |
| Macro | Recording, stop, playback, save-to-JavaScript, registered macros, reload, enablement, and permissions | 🟡 Partial | Core behavior exists, but Hidemaru macro-menu slots and invocation behavior have not been exhaustively mapped and tested. |
| Other | Settings, file-type profiles, key assignments, command list/menu editing, and font entry points | ❌ Incomplete | Add categorized history clearing, tags generation, free-cursor mode, settings save/restore, kana-kanji word registration or explicit native substitutes. |
| Help | MaruEdit guide, macro guide, shortcut reference, release check, support, and native About | ❌ Incomplete | Add configurable External Help 1–6 or document an explicit unsupported decision for each entry. |

The official pages contain roughly 297 command references, including repeated
placements, dynamic entries, and Windows-only commands. MaruEdit registers 175
stable command IDs plus dynamic and native-responder entries, so the raw totals
are not a parity measure. `ChromeParityAuditTests` only requires every existing
stable ID to appear exactly once in the command reference; it is a documentation
consistency check, not proof that the external Hidemaru inventory is complete.

## Toolbar and function-key strip

| Capability | Hidemaru | MaruEdit today | Status |
|---|---|---|---|
| Default editing buttons | File, clipboard, search/navigation groups | 21 colored SF Symbol buttons grouped as file, undo, clipboard, search, navigation and tools | 🟡 Native artwork; not pixel-identical |
| Add any command | Almost every command is eligible | Every registered stable MaruEdit command is eligible in toolbar and F-key customization | 🟡 Partial until the absent Hidemaru commands exist |
| Reorder buttons | Supported | Context-menu left/right movement with persistence | ✅ Complete |
| Add/remove separators | Supported | Separators are part of the ordered persistent layout | ✅ Complete |
| Hide/remove buttons | Supported | Context-menu add/remove commands | ✅ Complete |
| Reset defaults | Supported | Supported | ✅ Complete |
| Icon size/DPI | Automatic plus size choices | Native Retina scaling plus persistent Small/Medium/Large symbol sizes | ✅ Native equivalent |
| Text-only/fallback labels | Supported through definition JSON | Icons, icons plus text, or text-only; selection persists | ✅ Complete |
| Search box in toolbar | Supported/configurable | Persistent configurable inline search box executes unified search, highlighting and history | ✅ Complete |
| Floating toolbar | Supported on Windows | The command toolbar remains attached to its macOS document window; macOS has no native Hidemaru-style floating-toolbar window | 🟡 Explicit unsupported platform difference |
| Function-key strip | Configurable count/content and can merge with status bar | Twelve persistent assignable F-key slots, configurable visible count from 1–12, and optional physical-row merge with status bar | ✅ Complete |
| Enabled/toggle state | Buttons reflect current command availability/state | Toolbar and F-key buttons consume the same live registry-enabled and selected-state provider as menus and refresh after state changes | ✅ Complete |

## Status bar

| Field or action | Hidemaru | MaruEdit today | Status |
|---|---|---|---|
| Encoding, line ending, BOM | Display and click menus | Display and click menus | ✅ Complete |
| Read-only/view mode | Conditional state | Distinct conditional Read-Only and View Mode states | ✅ Complete |
| Cursor line/column | Display; click opens Go To | Display; click opens Go To Line | ✅ Complete |
| Selection characters/ranges | Display | Display | ✅ Complete |
| Selection line count/BOX dimensions | Display | Selection line count and live BOX width×height are displayed | ✅ Complete |
| Total line/character count | Optional fields and configurable calculation | Displayed and field-configurable; clicking opens persisted weights for full/half-width characters, both spaces, tabs, and line breaks with fractional rounding | ✅ Complete |
| Character code at cursor | Encoding-aware display; click details | Unicode display for Unicode files, Shift-JIS-preferred display for Japanese legacy files, and a details alert containing Unicode, UTF-8, Windows-31J, and current-encoding bytes | ✅ Complete |
| Insert/overwrite | Display; click toggles | Display and click toggles | ✅ Complete |
| Font size | Display; click slider/reset | Display; click opens an 8–72 pt live slider with reset to the pre-adjustment size | ✅ Complete |
| File-type profile | Display; click list | Displays and applies complete user/built-in profiles, with syntax-only overrides | ✅ Complete |
| CapsLock | Optional field | Conditional configurable CAPS indicator | ✅ Complete |
| Vertical/horizontal and column count | Display/click | HORZ/VERT/COL×n and a checked menu that toggles horizontal, vertical, or continuous column layout; the live count follows TextKit flow | ✅ Complete |
| Macro recording | Conditional state/click | Distinct REC and MACRO states are shown; clicking REC stops the active recording through the coordinator | ✅ Complete |
| Large-file mode | No direct equivalent | MaruEdit-specific safety field | ✅ Native addition (not a parity claim) |
| Configurable fields/clickability | Fields and global click enablement are configurable | Right-click field selection plus a persistent global click-action switch | ✅ Complete |
| Merge with function-key strip | Supported | Persistent merge shares one 24pt row and restores full-width F-key layout when status is hidden | ✅ Complete |

## Acceptance gates

1. ❌ **Incomplete** — Every compatible Hidemaru menu entry has a stable `CommandID`, enabled
   state, menu placement, documentation, and an executable test.
2. 🟡 **Partial** — Platform-specific entries have a documented native mapping or an explicit
   unsupported reason; placeholders do not count.
3. ✅ **Complete** — Toolbar configuration stores ordered command IDs and separators, supports
   add/remove/reorder/reset, and reflects command enabled/toggle state.
4. ❌ **Incomplete** — Status fields are individually configurable, interactive where Hidemaru is
   interactive, and remain correct across tabs, IME, BOX/multi-selection,
   encodings, large files, and profile changes.
5. 🟡 **Partial** — Default and customized chrome have screenshot baselines in light/dark and
   narrow/wide windows, plus keyboard-only and accessibility verification.

Gate notes:

- Gate 1 needs an external Hidemaru-command inventory. Auditing only MaruEdit's
  existing 175 IDs cannot detect commands that MaruEdit never registered.
- Gate 2 is complete for the floating-toolbar decision but not for every Windows-
  specific menu/frame/window command.
- Gate 3 covers persistence, layout operations, configurable F-key count, and
  live enabled/toggle synchronization in `ClassicWorkspaceTests`.
- Gate 4 has strong field-level tests but still lacks the interactions identified
  in the status table and a complete cross-state matrix.
- Gate 5 has all eight screenshot baselines and basic keyboard/accessibility tests;
  full keyboard traversal, focus-order, and VoiceOver verification remain open.

## Acceptance evidence

The checked-in visual regression matrix is generated by
`ChromeSnapshotTests` and compares fresh rendering with the baseline at sampled
pixel level (not merely file existence). Narrow customized windows deliberately
clip the fixed, ordered command strip at the trailing edge, matching a classic
non-wrapping toolbar; commands remain available through menus and keyboard.

| Configuration | Light | Dark |
|---|---|---|
| Default, narrow | [baseline](screenshots/chrome/default-light-narrow.png) | [baseline](screenshots/chrome/default-dark-narrow.png) |
| Default, wide | [baseline](screenshots/chrome/default-light-wide.png) | [baseline](screenshots/chrome/default-dark-wide.png) |
| Customized, narrow | [baseline](screenshots/chrome/custom-light-narrow.png) | [baseline](screenshots/chrome/custom-dark-narrow.png) |
| Customized, wide | [baseline](screenshots/chrome/custom-light-wide.png) | [baseline](screenshots/chrome/custom-dark-wide.png) |

Regenerate intentionally with `UPDATE_CHROME_SNAPSHOTS=1 swift test --filter
ChromeSnapshotTests`. `ClassicWorkspaceTests`, `FindBarViewTests`,
`MenuCustomizationUITests`, and `KeyBindingManagerTests` cover accessibility
labels, keyboard-only search/options, the full menu hierarchy, configurable
F-key activation, and user key bindings. `ChromeParityAuditTests` checks internal
command-document consistency; Gate 1 remains open until the external command
inventory is mapped.

## Primary sources

- Hidemaru 9.57 menu pages (`225_amnl*.html`), official help
- Toolbar detail and toolbar design, official help
- Status bar detail (`070_Env_Win_Statusbar.html`), official help
- Command value list and tab/window management, official help
