# Maru Chrome Parity Matrix

Baseline: Maru Editor 9.57 official help, compared with MaruEdit `main`.
This matrix covers application chrome only: menus, command toolbar, function-key
strip, and status bar. Windows-only shell integrations use a native macOS
equivalent and must never be reported as byte-for-byte parity.

Status legend:

- ✅ **Complete** — the compatible behavior is implemented and has direct test evidence.
- 🟡 **Partial / native substitute** — useful coverage exists, but behavior, scope, or
  verification is not yet equivalent.
- ❌ **Incomplete** — a confirmed compatible Maru capability is absent or an
  acceptance requirement is not met.

Overall status: **100% aligned for the compatible Maru 9.57 chrome scope**.
Windows-owned lifecycle, IME and mounted-remote-volume operations are explicitly
verified native mappings rather than byte-for-byte platform claims.

## Evidence, naming, and network policy

Compatibility work is offline-first. MaruEdit does not automatically search the
web for Maru behavior and contributors must ask the user before any specific
online lookup. Evidence is accepted in this order:

1. behavior observed by the user in Version 9.57;
2. locally supplied bundled help, consulted without copying or redistributing it;
3. screenshots and settings supplied by the user; and
4. the independently written inventories and notes checked into this repository.

Unverified recollection is not sufficient to mark an item complete. Code and
documentation use the neutral name **Maru** and must not contain legacy-editor
branding, website links, copied help text, screenshots, icons, or other protected
resources. MaruEdit's own Help is bundled and offline. Online update, support,
dictionary, and configured external-help destinations require an explicit
confirmation before macOS opens them.

| Area | ✅ Complete | 🟡 Partial/native | ❌ Incomplete |
|---|---:|---:|---:|
| Menu rows | 13 | 0 | 0 |
| Toolbar/function-key rows | 12 | 0 | 0 |
| Status-bar rows | 16 | 0 | 0 |
| Acceptance gates | 5 | 0 | 0 |

## Menu bar

Maru's documented top-level business menus are File, Edit, Convert,
View, Insert, Search, Highlight, Bookmark, Tools, Window, Macro, Other, and
Help. macOS additionally requires the application menu; MaruEdit keeps that
native menu before the Maru-compatible business menus.

### Default menu profile and expansion requirement

MaruEdit must distinguish Maru's default menu profile from its complete
command inventory. A fresh profile shows the same seven business menus as
Maru 9.57: **File, Edit, View, Search, Window, Macro, Other** (plus the
mandatory macOS application menu). **Convert, Insert, Highlight, Bookmark,
Tools, and Help are installed but hidden by default.**

`Other → Customize Menus…` exposes an **Extended Top-Level Menus** section that
can enable those six menus individually. Enabling all six restores the complete
13-menu hierarchy and every registered command remains independently selectable;
restoring defaults returns to the seven-menu profile. This follows Maru's
official distinction between the compact menu bar and `メニューバー編集`, while
User Menu 1–8 remains the freely reorderable mechanism. The behavior is frozen
by `MenuCustomizationTests` and `MenuCustomizationUITests`.

The seven menus are also compact at the command level. Their initial command
profile is deliberately limited to the daily surface below; native macOS items
such as Undo, Cut, Copy, Paste, Select All, Minimize, and Zoom, plus dynamic
Recent Files, Encoding, Registered Macros, and open-window entries remain
visible where applicable.

| Default menu | Initial MaruEdit command surface |
|---|---|
| File | New, Open, Reload, Save, Save As, Close, Page Setup, Print |
| Edit | Repeat Last Operation, plus native editing commands |
| View | Toolbar, line numbers, ruler, function keys, status bar, wrapping, fonts, full screen |
| Search | Find, upward find, replace, next/previous, go to line, Grep, Grep Replace |
| Window | Common vertical/horizontal/cascade arrangement, tab and window traversal |
| Macro | Record, play, save recording, run, plus registered macros |
| Other | Settings, file-type/key/menu configuration, command list, bundled guide |

Every other registered command starts unchecked in **Customize Menus** and can
be added back individually. Explicit additions and removals persist by stable
command ID; **Restore Default Menus** clears those overrides and restores this
compact profile. No command implementation is removed.

| Maru menu | MaruEdit today | Status | Remaining gap |
|---|---|---|---|
| File | New/open/partial/binary, close-and-open, encoding reopen, reload, properties, rename, View Mode, edit-preserving overwrite prohibition, append save/read, print/page setup, complete save/close/discard variants, cursor-target opening, project folders, desktop/workspace save/open/history, WebKit browse mode, and suspendable file/folder/workspace history | ✅ Complete | All 42 official 9.57 File rows are mapped and placement-tested. Maru Project/Desktop files map to folder projects and `.maruedit-workspace`; Quit/Close use macOS lifecycle conventions; FTP/SFTP/WebDAV files use Finder-mounted remote volumes and native Open/Save panels. |
| Edit | Undo/clipboard, repeat-last-edit, append cut/copy, line-boundary and word deletion, histories, quoted/BOX/history paste, deletion restore, inverted/reserved/multiple selections, Caps Lock correction, and native IME reconversion | ✅ Complete | Every confirmed compatible edit gap is implemented through stable commands and multi-selection-aware undo transactions. Physical Caps Lock state remains macOS-owned; text correction and IME reconversion use native AppKit paths. |
| Convert | Case, generic and selective half/full-width, hiragana/katakana, Tab/space conversions, and ordered conversion pipelines | ✅ Complete | “Conversion Pipeline…” provides built-in and persistent named presets, ordered add/remove/reorder controls, parameterized literal/regex/whitespace modules, one-step multi-selection Undo, and a tested registration API for external conversion modules. |
| View | Independent toolbar/function-key/status/heading/ruler/gutter visibility, wrapping, invisibles, ruler marks and profile tab stops, native automatic spelling, character code/count entry points, redraw, editable vertical writing, continuous column flow, splits, partial editing/folding, full screen, Files/Outline/Results/Browser panes, and output-pane focus | ✅ Complete | All 25 official 9.57 View rows are mapped and placement-tested. Browser frames use an embedded accessible WebKit pane with document/shared entry points; folding controls have an independent gutter switch. |
| Insert | Date/time, newline, tab, page break, duplicate line, indentation-preserving blank line, C0/DEL control codes, deletion restore, current filename, and encoding-aware file-content insertion | ✅ Complete | Every compatible command in the official 9.57 insertion-command inventory is placed in the Insert menu and covered by executable tests; MaruEdit additionally exposes templates and file-content insertion. |
| Search | Search/replace/Grep Replace, case/word/regex/fuzzy flags, return to search start, the complete cursor-navigation inventory, edit marks, all-match selection/list/outline/color operations, document-local persistent color layers, line marks, temporary color markers, search ranges, and unified/dedicated Grep-result navigation | ✅ Complete | Every compatible entry on the official 9.57 Search menu has a stable command, menu placement, documentation, and direct registry or behavior test. Unified result navigation follows Maru's difference → search color → Grep priority. |
| Highlight | Outline analysis, highlighted-line navigation/area selection, persistent line markers, and temporary selection-range color markers | ✅ Complete | The official Highlight submenu and Temporary Color Marker submenu are mapped: configure/apply, selection-intersection removal, clear all, convert markers to multiple selections, bidirectional wrap navigation, edit tracking, and profile-aware highlighted-line commands have direct tests. |
| Bookmark | Toggle, previous/next, clear, and a document list with jump/remove | ✅ Complete | No confirmed compatible gap in the scoped bookmark row; retain official-command regression coverage. |
| Tools | Eight persistent ordered user menus, six external-help slots, dynamic external programs, Finder and macro-folder access, compare/difference, deterministic portable tags generation and navigation, settings transfer, file-type/environment/key/menu settings, categorized history clearing, and the complete command list | ✅ Complete | Every compatible official 9.57 Tools entry is mapped. User menus accept ordered stable CommandIDs and separators and rebuild live. Windows Explorer maps to Finder; external programs remain permission-scoped and stream through the shared Output pane. Tags generation is bounded, skips dependency/hidden trees, writes atomically, and feeds Tag Jump directly. |
| Window | Native vertical/horizontal/grid/cascade arrangement, minimize-all, topmost/full-screen state, horizontal/vertical editor splits, split and cross-window linked scrolling, compare/difference, workspace save/restore, Files/Outline/Output/WebKit panes, tab cycling/list/close scopes, ownership-preserving tab detach into managed windows, current/all-window cycling including minimized windows, previous-active activation, and native Minimize/Zoom | ✅ Complete | All 43 official 9.57 Window rows are mapped and placement-tested. Managed `NSWindow`s replace Maru's process-per-editor model; minimized windows restore during inclusive cycling, and browser-frame commands use the embedded WebKit utility pane. |
| Macro | Start/stop recording, single and bounded repeat playback, non-overwriting JavaScript save, run chooser, metadata-driven registered macros, reload, folder access, enablement, shortcuts, permissions, output/errors, and macro help | ✅ Complete | The official 9.57 Macro inventory is mapped. Maru's “load key operations” is represented by loading/reloading saved JavaScript recordings into the registered-macro catalog; persistent named macros replace fixed Windows macro slots while retaining keyboard assignment and menu invocation. |
| Other | Settings, file-type profiles, key assignments, command/menu editing, font entry points, categorized history clearing, tag navigation/generation, control-code input, native spelling corrections, View Mode, overwrite protection, free cursor, vertical/column layout, and full/section settings transfer | ✅ Complete | Every compatible official 9.57 Other entry has a stable placement. Windows-only input-method operations use native macOS settings and input-source workflows; an online system guide can be opened only after confirmation. |
| Help | Bundled MaruEdit PDF manual; configurable External Help 1–6; opt-in online release/support destinations; and native About | ✅ Complete | The first-party `maruedit.pdf` manual is packaged with the application and never needs a network connection. Main, macro, and shortcut help open that manual. Local external-help files open directly; every HTTP(S) destination asks before opening. Online commands remain available through menu customization but are absent from the compact default surface. About uses the native macOS panel. |

The checked-in [official 9.57 inventory](maru-9.57-menu-inventory.tsv)
contains 336 rows extracted from the 13 official pages, including repeated
placements, dynamic entries, submenus, commands that are bindable but absent
from the menu bar, and Windows-only commands. MaruEdit registers 328
stable command IDs plus dynamic and native-responder entries, so the raw totals
are not a parity measure. `ChromeParityAuditTests` freezes the official per-menu
counts, schema, placement classification, uniqueness, and cross-menu sentinels,
in addition to requiring every stable ID to appear exactly once in the command
reference. All 336 rows have audited dispositions; stable targets are recursively
verified in their corresponding live AppKit menu.

## Toolbar and function-key strip

| Capability | Maru | MaruEdit today | Status |
|---|---|---|---|
| Default editing buttons | File, clipboard, search/navigation groups | 21 colored Retina SF Symbol buttons grouped as file, undo, clipboard, search, navigation and tools | ✅ Verified native artwork equivalent |
| Add any command | Almost every command is eligible | Every registered stable MaruEdit command is eligible in toolbar and F-key customization | ✅ Complete |
| Reorder buttons | Supported | Context-menu left/right movement with persistence | ✅ Complete |
| Add/remove separators | Supported | Separators are part of the ordered persistent layout | ✅ Complete |
| Hide/remove buttons | Supported | Context-menu add/remove commands | ✅ Complete |
| Reset defaults | Supported | Supported | ✅ Complete |
| Icon size/DPI | Automatic plus size choices | Native Retina scaling plus persistent Small/Medium/Large symbol sizes | ✅ Native equivalent |
| Text-only/fallback labels | Supported through definition JSON | Icons, icons plus text, or text-only; selection persists | ✅ Complete |
| Search box in toolbar | Supported/configurable | Persistent configurable inline search box executes unified search, highlighting and history | ✅ Complete |
| Floating toolbar | Supported on Windows | The same live toolbar detaches into a persistent resizable floating `NSPanel` and docks without losing layout, search, or command state | ✅ Complete |
| Function-key strip | Configurable count/content and can merge with status bar | Twelve persistent assignable F-key slots, configurable visible count from 1–12, and optional physical-row merge with status bar | ✅ Complete |
| Enabled/toggle state | Buttons reflect current command availability/state | Toolbar and F-key buttons consume the same live registry-enabled and selected-state provider as menus and refresh after state changes | ✅ Complete |

## Status bar

| Field or action | Maru | MaruEdit today | Status |
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
| Cursor position placement | Compact line:column indicator at the far right of the menu-level top row | macOS reserves the system menu bar's right side, so Classic uses the nearest per-window equivalent: a right-aligned title-bar accessory above the toolbar, and suppresses the duplicate bottom-left field; Modern keeps the native status-bar field | ✅ Native equivalent |
| Merge with function-key strip | Supported | Persistent merge shares one 24pt row and restores full-width F-key layout when status is hidden | ✅ Complete |

## Acceptance gates

1. ✅ **Complete** — Every compatible Maru menu entry has a stable `CommandID`, enabled
   state, menu placement, documentation, and an executable test.
2. ✅ **Complete** — Platform-specific entries have a documented native mapping or an explicit
   unsupported reason; placeholders do not count.
3. ✅ **Complete** — Toolbar configuration stores ordered command IDs and separators, supports
   add/remove/reorder/reset, and reflects command enabled/toggle state.
4. ✅ **Complete** — Status fields are individually configurable, interactive where Maru is
   interactive, and remain correct across tabs, IME, BOX/multi-selection,
   encodings, large files, and profile changes.
5. ✅ **Complete** — Default and customized chrome have screenshot baselines in light/dark and
   narrow/wide windows, plus keyboard-only and accessibility verification.

Gate notes:

- Gate 1 has a checked-in 336-row external Maru inventory, exhaustive per-row
  mappings, registered/documented target checks, and recursive live-menu placement tests.
- Gate 2 has no unexplained unsupported rows. Windows lifecycle, IME, About and
  remote-volume operations have explicit native mappings; browser frames and the
  floating toolbar now have real WebKit/NSPanel implementations.
- Gate 3 covers persistence, layout operations, configurable F-key count, and
  live enabled/toggle synchronization in `ClassicWorkspaceTests`.
- Gate 4 has field-level interaction tests, a cross-state matrix covering tab
  transitions, BOX/multi-selection, Unicode and legacy encodings, line endings,
  profile changes and large-file modes, the existing marked-text IME suite, and
  executable VoiceOver Press actions for all twelve interactive fields.
- Gate 5 has all eight screenshot baselines, an explicit wrapping forward/reverse
  focus loop across toolbar, F-key strip, Find/Replace, tabs, editor, sidebar,
  output and status fields, first-responder verification for every member, and
  executable VoiceOver Press tests for tabs, tab closing and status actions.

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
command-document consistency, all 336 official mappings, native-platform target
classification, and recursive stable-command placement in the live menu tree.

## Locally recorded evidence

- Checked-in 9.57 menu inventories and independently written mappings
- User-observed Version 9.57 menu, tab, ruler, cursor-position, toolbar, and status behavior
- Local bundled-help page identifiers recorded as provenance only; the original
  files and prose are not redistributed
