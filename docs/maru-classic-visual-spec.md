# Maru Classic visual specification

Maru Classic is a clean-room macOS workspace for users whose muscle memory
comes from dense, keyboard-oriented Japanese editors. It recreates layout,
information density, and command placement, while using original code, SF
Symbols, native AppKit controls, and MaruEdit branding. It does not copy
Hidemaru artwork, binaries, icons, or trademarks.

## Reference structure

Public Hidemaru documentation consistently presents this vertical hierarchy:
menu, one-click toolbar, tabs, auxiliary pane/editor, and segmented status
information. Older and current descriptions also document the character ruler,
top toolbar, bottom function-key display, and user-selectable toolbar contents.

- <https://hide.maruo.co.jp/software/hidemaru8/index.html>
- <https://stakiran.github.io/ebook_hidemarueditor/preview.html>
- <https://hidemaru.iinaa.net/helpsite/hidemaru7/html/070_Env_Win_ToolbarDesign.html>

## Shipped geometry

| Region | Classic metric | Behavior |
|---|---:|---|
| Command toolbar | 32 pt | 27 pt icon cells, six separated command groups |
| Tab row | 32 pt | compact rectangular tabs, modification and close indicators |
| Current heading | 22 pt | active outline/document heading |
| Character ruler | 20 pt | columns, five-column ticks, ten-column labels |
| Function strip | 24 pt | F1–F6 labels; implemented commands are clickable |
| Status row | 24 pt | cursor, selection, indentation, mode, newline, BOM, encoding, profile |

The default command bar exposes file creation/open/save/print, undo/redo,
cut/copy/paste, Find/Replace/next/previous/Grep, bookmarks, go-to-line,
folding, the Macro menu, utility-pane control, and Settings. Right-clicking it opens a
show/hide checklist and restores the default layout. All product-specific
actions use stable Command Registry identifiers.

Icons use an original semantic palette instead of a monochrome strip: blue for
file and navigation operations, yellow for folders, purple for print/replace/
folding, red/orange for destructive or marker operations, green for directional
search, cyan for Grep, and pink for macros. Hovering gives each 27 pt cell a
subtle rounded highlight without changing its command color.

## Acceptance

- The system titlebar contains no large icon-and-label toolbar.
- The compact command bar appears above tabs in Classic mode only.
- At 1100 pt window width every default command remains visible.
- Toolbar, ruler, heading, function strip, and status fields expose accessible
  labels; keyboard commands remain available when a visual item is hidden.
- Switching to Modern changes presentation only and never document text.
- A screenshot from the built app is visually reviewed after geometry changes.
