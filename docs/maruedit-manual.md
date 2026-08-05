# MaruEdit User Manual

Version 1.0 · macOS 13 or later

MaruEdit is a native, keyboard-first text editor for macOS. It is designed for
fast plain-text editing, reliable Japanese text formats, powerful search and
Grep, and a configurable classic workspace.

## 1. Getting Started

### Create, open, and save

- Choose File → New to create a document.
- Choose File → Open to open a file or a project folder.
- Choose File → Save or Save As to write the active document.
- Drag files onto MaruEdit or its Dock icon to open them.

MaruEdit tracks external file changes. If another application changes, moves,
or deletes an open file, MaruEdit asks how to proceed instead of silently
overwriting either version. Unsaved recovery data is kept separately.

### Tabs and windows

A single document does not show the tab row by default. Opening a second
document reveals tabs. Tab placement and single-tab visibility can be changed
in Settings. Tabs can be reordered, detached, or selected from Window.

## 2. The Maru Classic Workspace

Maru Classic is the default workspace. It contains a compact command toolbar,
character ruler, optional function-key strip, editor, line-number gutter, and
status fields. Each component can be shown or hidden independently.

The default ruler and wrapping reference is 160 columns. Change wrapping mode,
fixed width, tab width, and ruler marks in Settings. Toolbar buttons use colored
original symbols and may show icons, icons with text, or text only. Commands can
be added, removed, reordered, or placed on the function-key strip.

The compact menu profile initially shows File, Edit, View, Search, Window,
Macro, and Other. Choose Other → Customize Menus to add individual commands or
enable extended top-level menus. Restoring defaults returns to the compact
profile without deleting commands.

## 3. Editing

### Selection modes

MaruEdit supports normal selections, multiple selections, and rectangular BOX
selections. Editing commands operate on all active selections as one undoable
transaction. BOX operations preserve visual columns across tabs and full-width
characters.

### Common operations

- Undo and Redo use standard macOS shortcuts.
- Repeat Last Operation repeats the most recent eligible edit command.
- Line commands include duplicate, join, sort, reverse, indent, and outdent.
- Conversion covers case, width, kana, tabs, spaces, and reusable pipelines.
- Insert commands include date/time, filenames, control codes, and file contents.

### Input methods

Marked text remains attached to the primary selection during composition. When
composition is committed, final text is replicated safely to secondary
selections. Input-source switching and dictionary management remain native.

## 4. Search, Replace, and Grep

Choose Search → Find to open the unified find bar. Literal and regular-expression
search share case, whole-word, fuzzy, range, and history settings. Replace
supports one replacement, replace-and-find, or Replace All with one undo step.

Grep searches a folder recursively and streams results into Results. Filters,
hidden-file handling, symbolic-link policy, encoding, cancellation, and limits
are configurable. Grep Replace first creates a preview. Modified open documents
and unsafe paths are protected from silent replacement.

Matches can be selected together, listed, outlined, colored, or converted to
persistent markers. Navigation covers colors, differences, Grep results,
bookmarks, edit marks, and highlighted lines.

## 5. Text Formats and Files

MaruEdit detects UTF-8, UTF-16, UTF-32, Windows-31J, EUC-JP, and ISO-2022-JP.
Encoding and BOM are tracked separately. LF, CRLF, CR, and mixed line endings
are detected independently. Use status fields or File commands to reopen with a
specific encoding or choose the format used by Save As.

Files at or above 10 MiB require confirmation and use reduced read-only mode.
Files above 256 MiB are refused by default. File-type profiles select syntax,
encoding, line ending, wrapping, ruler, and display defaults by extension.
Project folders provide a file tree, quick open, Grep, tags, and restoration.

## 6. Status Bar and Navigation

Status can show encoding, line ending, BOM, selection size, total characters,
character code, insert/overwrite state, font size, profile, layout, recording,
Caps Lock, and large-file mode. Right-click it to choose fields.

In Maru Classic, the current line and column appear at the upper-right of the
window title row. Activate the indicator to open Go To Line. The ruler tracks
the horizontal editor origin and current display column.

Bookmarks, edit marks, tags, outlines, highlighted lines, and Results provide
independent navigation. Window commands support tabs, managed windows, editor
splits, linked scrolling, comparison, and saved workspaces.

## 7. Keyboard and Menus

Key bindings use stable command identifiers and can be imported or exported as
JSON. The macOS Standard and Maru Classic profiles may be restored. Two-step
chords are supported and never consume marked input-method text.

Common defaults:

- Command-O: Open
- Command-S: Save
- Command-F: Find
- Command-G / Shift-Command-G: Find next / previous
- Command-L: Go to line
- Command-comma: Settings

Choose Other → Key Assignments for the live list. Choose Other → Command List
to inspect every command, including commands hidden by compact menus.

## 8. Macros and External Commands

MaruEdit loads UTF-8 JavaScript macros from:

~/Library/Application Support/MaruEdit/Macros

Use Macro → Open Macro Folder, edit or add a file, then reload macros. Clipboard,
other-file, and external-command capabilities require declared permissions and
user approval. Network access is unavailable to macros.

Recording captures stable command identifiers and can be played repeatedly or
saved as a registered macro. External commands require configuration and
permission, stream output to Output, and can be cancelled.

## 9. Settings and Appearance

Settings cover appearance, editing, files, search, keyboard, macros, and
advanced behavior. Themes, fonts, line numbers, invisibles, ruler options,
wrapping, tabs, toolbar, function keys, and status fields are persistent.
Settings can be exported, imported by section, or restored to defaults.

The Modern workspace remains available as a native macOS alternative. Switching
workspace or theme does not alter document text.

## 10. Help, Privacy, and Safety

This manual is bundled inside MaruEdit as maruedit.pdf and opens locally. It
does not require an internet connection. Online update, support, dictionary,
and configured HTTP(S) external-help commands show the destination and ask for
confirmation before macOS opens a browser. Cancelling performs no network-facing
action. Local external-help files open directly.

MaruEdit uses atomic saving where possible, guards external-change conflicts,
limits expensive large-file operations, blocks macro network access, and keeps
external execution permission-scoped. Review previews before bulk replacement
and keep independent backups of important data.

## 11. Troubleshooting

If a command is missing, open Customize Menus or Command List; compact defaults
hide commands but do not remove them. If a shortcut does not run, inspect the
active profile for duplicate or ambiguous sequences. If text opens incorrectly,
reopen it with an explicit encoding before editing. If a macro is absent, confirm
it is UTF-8 and enabled, reload macros, and inspect Macro Error Console.

Online destinations open only when you choose an explicitly named Online
command and approve the displayed destination. Opening this manual never opens
a network resource.
