# Hidemaru Chrome Parity Matrix

Baseline: Hidemaru Editor 9.57 official help, compared with MaruEdit `main`.
This matrix covers application chrome only: menus, command toolbar, function-key
strip, and status bar. Windows-only shell integrations use a native macOS
equivalent and must never be reported as byte-for-byte parity.

## Menu bar

Hidemaru's documented top-level business menus are File, Edit, Convert,
View, Insert, Search, Highlight, Bookmark, Tools, Window, Macro, Other, and
Help. macOS additionally requires the application menu; MaruEdit keeps that
native menu before the Hidemaru-compatible business menus.

| Hidemaru menu | MaruEdit today | Gap |
|---|---|---|
| File | File | Reload, properties, rename, View Mode, append save/read, bounded partial open and close-and-open are present; missing save-and-exit variants, project/desktop histories and binary mode |
| Edit | Edit | Core clipboard/Undo and line editing exist; missing clipboard history, quote copy/paste, restore deletion, kana/CapsLock correction and several selection commands |
| Convert | Dedicated Convert menu | Case, half/full-width, hiragana/katakana and Tab/space conversions are present | No known compatible gap |
| View | View | Wrapping, invisibles, splits exist; missing ruler modes, tab-stop display, vertical/column layouts and several pane commands |
| Insert | Dedicated Insert menu | Date/time, page break and encoding-aware file-content insertion are present; missing control-code insertion |
| Search | Dedicated Search menu | Search/replace/grep core exists; missing Hidemaru hierarchy, search flags, highlight/refine variants and edit-mark navigation |
| Highlight | Dedicated Highlight menu | Color-marker operations are present; highlight-list commands are missing |
| Bookmark | Dedicated Bookmark menu | Toggle/navigation/clear are present; list and organize operations are missing |
| Tools | Empty dynamic menu | External commands exist; project/tag/compare commands need compatible grouping and command-list access |
| Window | Native window controls plus tab cycling | Missing tab list, close-range entries in menu, pane focus and desktop/window arrangement equivalents |
| Macro | Dynamic Macro menu | Recording/playback and registration management remain incomplete |
| Other | Dedicated Other menu | Settings, font panel and menu editing are grouped; file-type profiles, key assignment and command list need direct entries |
| Help | Dedicated Help menu plus native About | Documentation entry is present; missing macro help, shortcut reference and update/support entries |

Official menu pages contain roughly 297 command references across these
menus. MaruEdit currently registers 111 stable command IDs. Duplicate menu
placements mean this is not a one-to-one command count, but it establishes
that functional parity is not complete.

## Toolbar and function-key strip

| Capability | Hidemaru | MaruEdit today | Status |
|---|---|---|---|
| Default editing buttons | File, clipboard, search/navigation groups | 21 colored SF Symbol buttons in similar groups | Partial |
| Add any command | Almost every command is eligible | Every registered stable command is eligible in toolbar and F-key customization | Present |
| Reorder buttons | Supported | Context-menu left/right movement with persistence | Present |
| Add/remove separators | Supported | Separators are part of the ordered persistent layout | Present |
| Hide/remove buttons | Supported | Context-menu add/remove commands | Present |
| Reset defaults | Supported | Supported | Present |
| Icon size/DPI | Automatic plus size choices | Native scaling only | Partial/native equivalent |
| Text-only/fallback labels | Supported through definition JSON | Icons, icons plus text, or text-only; selection persists | Present |
| Search box in toolbar | Supported/configurable | Find Bar is separate | Partial |
| Floating toolbar | Supported on Windows | No native equivalent | Intentional platform difference |
| Function-key strip | Configurable and can merge with status bar | Twelve persistent configurable F-key slots; merge is not yet available | Partial |

## Status bar

| Field or action | Hidemaru | MaruEdit today | Status |
|---|---|---|---|
| Encoding, line ending, BOM | Display and click menus | Display and click menus | Present |
| Read-only/view mode | Conditional state | Distinct conditional Read-Only and View Mode states | Present |
| Cursor line/column | Display; click opens Go To | Display; click opens Go To Line | Present |
| Selection characters/ranges | Display | Display | Present |
| Selection line count/BOX dimensions | Display | Selection line count and live BOX width×height are displayed | Present |
| Total line/character count | Optional fields | Displayed and configurable | Present |
| Character code at cursor | Display; click details | Display and click details | Present |
| Insert/overwrite | Display; click toggles | Display and click toggles | Present |
| Font size | Display; click adjustment | Display; click opens font panel | Present/native equivalent |
| File-type profile | Display; click list | Display; click language/profile menu | Partial |
| CapsLock | Optional field | Conditional configurable CAPS indicator | Present |
| Vertical/horizontal and column count | Display/click | Missing; vertical mode is not production-ready | Missing |
| Macro recording | Conditional state/click | Macro execution activity is shown; command recording is not implemented | Partial |
| Large-file mode | No direct equivalent | MaruEdit-specific safety field | Native addition |
| Configurable fields/clickability | Supported | Right-click field selection; interactive fields remain clickable | Present |
| Merge with function-key strip | Supported | Separate rows | Missing |

## Acceptance gates

1. Every compatible Hidemaru menu entry has a stable `CommandID`, enabled
   state, menu placement, documentation, and an executable test.
2. Platform-specific entries have a documented native mapping or an explicit
   unsupported reason; placeholders do not count.
3. Toolbar configuration stores ordered command IDs and separators, supports
   add/remove/reorder/reset, and reflects command enabled/toggle state.
4. Status fields are individually configurable, interactive where Hidemaru is
   interactive, and remain correct across tabs, IME, BOX/multi-selection,
   encodings, large files, and profile changes.
5. Default and customized chrome have screenshot baselines in light/dark and
   narrow/wide windows, plus keyboard-only and accessibility verification.

## Primary sources

- Hidemaru 9.57 menu pages (`225_amnl*.html`), official help
- Toolbar detail and toolbar design, official help
- Status bar detail (`070_Env_Win_Statusbar.html`), official help
- Command value list and tab/window management, official help
