# MaruEdit / Maru Product Gap Analysis

Audit date: 2026-08-05. Reference: Maru Editor 9.57 public product and
help pages. This is a clean-room comparison of publicly documented behavior.
It does not authorize copying Maru code, binaries, icons, screenshots,
help text, product dress, or trademarks.

## Executive conclusion

MaruEdit has a credible reliability core: explicit encoding/BOM/newline state,
atomic saves, external-change protection, recovery, Find/Replace, folder Grep,
Grep Replace preview, multiple/BOX selections, IME handling, key profiles,
file-type profiles, controlled macros, and controlled processes. Those are the
right foundations for a native macOS editor.

It is not yet a close Maru workflow replacement. The present window reads
as a small project/code editor: a large file-tree sidebar, custom dark tabs,
and a sparse editor/status area. Maru's recognizable working surface is a
dense document editor: menu and configurable toolbar, compact document tab,
optional outline/file/output pane, current-outline heading, horizontal ruler,
line-number/mark gutter, visible whitespace, function-key command strip, and a
segmented status bar. The product gap is therefore both interaction density and
feature breadth, not simply color matching.

## Capability matrix

| Area | Maru public behavior | MaruEdit now | Gap / decision |
|---|---|---|---|
| Encodings and newlines | Broad encoding controls, per-type load/save behavior | UTF plus principal Japanese legacy formats; BOM and LF/CRLF/CR modeled separately | Strong baseline; broaden candidate order and formats only from real fixtures |
| Search/Replace | Regex, multiline inputs, selection scope, history, markers | Literal/regex, capture replacement, scope, history | Add multiline expanding fields and persistent color-marker workflow |
| Grep | Disk, current content, open files, output document/pane, result refinement | Directory streaming, output pane, navigation, cancellation | Add current buffer/open documents, output document, and Grep-over-results |
| Grep Replace | Dialog-driven multi-file replace | Mandatory preview, atomic per-file writes and recovery | MaruEdit is safer; retain preview rather than imitate destructive defaults |
| Multiple/BOX selection | Multiple selection and column workflows | Supported with IME collapse and single undo | Close; add migration-compatible gestures/status cues |
| Basic editing | Extensive cursor, deletion, conversion, indentation commands | Core line commands and configurable keys | Add overwrite mode, richer word/paragraph commands, transpose and conversions |
| Bookmarks/markers | Bookmarks plus multiple color markers and marker lists | Bookmarks only | Color markers and a navigable marker list are a high-value gap |
| Outline | User-definable real-time outline, function/highlight lists, heading bar | File tree only | Major gap: build symbol/outline pane, current-heading bar, custom rules |
| Folding/partial edit | Folding and edit-only-selected-section workflows | None | Major long-document gap; folding first, partial edit later |
| Word completion | Manual/automatic completion from text, dictionaries and files | None | Major daily-use gap; start with current-document and user dictionaries |
| Spell checking | Automatic underline, context corrections and per-type language | TextKit may expose system spelling but no product-level controls | Add explicit per-profile system spell-check controls |
| File-type settings | Font, layout, tabs, colors, comments, outline, folding, completion, templates, spelling, save/load, backup | Tab/indent/wrap/encoding/syntax/comment profile | Model is much narrower; extend schema with migrations, not ad-hoc defaults |
| Syntax/highlighting | User-defined highlight groups and detailed color slots | Built-in regex language rules and a small theme | Add user rules, per-profile colors, bracket/tag matching and marker layers |
| Tabs/windows | Tab groups, ordering, saved desktops, split and linked scrolling | Tabs, independent windows, session restore | Add editor split, tab groups/order controls and optional linked scrolling |
| Compare/navigation | File comparison, tag/back-tag jump, external help | None | Add native diff/compare and tag/back stack; external help is lower priority |
| CSV/TSV | Table-oriented CSV/TSV mode | Plain text only | Useful specialist mode; defer until core Classic surface is stable |
| Vertical writing/columns | Vertical writing and multi-column display | None | Expensive and niche on macOS; post-compatibility target |
| Binary/large files | Binary mode and very large editable files | Binary refusal; large files reduced/read-only; 256 MiB cap | Do not promise parity until a streaming buffer replaces TextKit storage |
| Macro language | Mature C-like language with broad editor/window/process surface and library ecosystem | Controlled JavaScript API; eight-command experimental translator | Largest automation gap; expand clean-room translator by measured macro corpus |
| External extensions | DLL/modules, add-ins, dictionaries, icon modules | Controlled external commands; no plug-in ABI | Preserve security boundary; dictionaries/themes are safe, arbitrary native plug-ins are not a 1.x goal |
| Print | Dedicated and add-in-enhanced printing | None | Add native macOS print/page setup before advanced publishing |
| Accessibility/readout | Reader integration and detailed readout settings | AX labels/keyboard tests; VoiceOver manual Gate pending | Complete real VoiceOver navigation before claiming parity |
| Configuration | Very deep basic/advanced environment tree | Focused Settings window | Add searchable Basic/Advanced settings and import/export/reset by section |
| Startup/resident mode | Resident process and near-zero subsequent launch | Native launch, currently above target | macOS should improve cold launch; do not reproduce a Windows tray resident process |

## Visual and interaction target

The goal should be **familiar information architecture with native macOS
rendering**, not a pixel clone.

```text
macOS title bar + native menus
┌─────────────────────────────────────────────────────────────────────┐
│ configurable compact toolbar: New Open Save Undo Find Grep Macro   │
├─────────────────────────────────────────────────────────────────────┤
│ compact document tabs                                               │
├──────────────┬──────────────────────────────────────────────────────┤
│ Outline /    │ current symbol or heading bar                        │
│ Files /      ├──────────────────────────────────────────────────────┤
│ Results      │ horizontal column ruler                              │
│ switcher     ├───┬──────────────────────────────────────────────────┤
│              │ # │ editor                                           │
│              │   │                                                  │
├──────────────┴───┴──────────────────────────────────────────────────┤
│ optional function-key / favorite-command strip                      │
├─────────────────────────────────────────────────────────────────────┤
│ Ln/Col │ encoding │ newline │ insert/overwrite │ selection │ syntax │
└─────────────────────────────────────────────────────────────────────┘
```

Required visual changes:

1. Replace the permanently dominant file tree with a switchable **Files /
   Outline / Results** utility pane; default the pane closed for single-file
   launches.
2. Add a native customizable toolbar and a compact tab style. Preserve macOS
   title-bar behavior, full-screen controls, vibrancy, focus rings, and system
   accessibility.
3. Add an optional current-heading bar and horizontal character ruler above
   the text. Align the ruler with tabs and full-width character display cells.
4. Make the gutter carry line numbers plus bookmark/fold/marker states.
5. Add an optional favorite-command/function-key strip. Labels come from the
   active key profile and Command Registry, never hard-coded screenshots.
6. Expand the status bar into stable clickable segments, including
   insert/overwrite and selection/BOX state.
7. Ship **Maru Classic Light** as the migration default and retain the current
   dark appearance as **Maru Modern Dark**. Use original colors/SF Symbols;
   never package Maru icons or bitmaps.

## Prioritized compatibility backlog

### P0 — adoption surface

- Classic workspace layout and Light theme.
- Native toolbar, compact tabs, pane switcher, ruler and segmented status bar.
- Outline/symbol pane plus current-heading bar.
- Code/text folding.
- Overwrite mode with IME, multiple-selection and undo tests.
- Split editor and linked-scroll option.
- Current-document completion and user dictionary completion.
- Multiline Find/Replace fields and color markers.
- Real VoiceOver smoke test for the complete Classic surface.

### P1 — daily Maru workflows

- Grep current unsaved content, all open documents, output-as-document and
  result refinement.
- File compare/diff, next/previous difference and linked scrolling.
- Tag jump, back-tag stack and symbol navigation.
- Expanded file-type profiles: font/colors, spelling, completion, outline,
  folding, templates, backup and load/save policy.
- Native print and page setup.
- Searchable Basic/Advanced settings with import/export/reset.
- Broader clean-room macro compatibility chosen from a legal, redistributable
  regression corpus.

### P2 — specialist parity

- CSV/TSV table mode.
- Partial editing of a selected outline region.
- Vertical writing and column layout.
- Streaming editable huge-file architecture and explicit binary view.
- Richer theme/dictionary packs and a reviewed extension API.

## What should intentionally remain different

- Grep Replace keeps preview, conflict detection and recovery.
- Macros remain capability-based; compatibility must not expose arbitrary
  Objective-C, filesystem, network, shell, or native DLL access implicitly.
- Native plug-ins, Windows registry integration, tray residency, Windows file
  dialogs and Windows-only add-ins are not compatibility requirements.
- MaruEdit retains macOS shortcuts, input methods, accessibility and security;
  the Maru Classic profile supplies familiar alternatives without fighting the
  platform.

## Acceptance criteria for “credible Maru alternative”

A Windows Maru user should be able to install MaruEdit, choose **Maru
Classic**, and within ten minutes find the toolbar, outline, ruler, markers,
status segments, familiar search/Grep scopes, completion, split/compare, keys,
file-type settings and macros without reading source code. A usability test
with at least five experienced Maru users should complete a scripted task
set and record time, errors, missing commands and subjective familiarity. Visual
similarity alone is not a pass if daily workflows remain absent.

Implementation is tracked in the executable [Maru Classic roadmap](maru-classic-roadmap.md).
