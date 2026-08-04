# Status Bar Coordinates and Format Controls

The status bar reports cursor and selection state through
`EditorCursorState`; its coordinate fields intentionally use different names
and units:

- `lineNumber` is one-based.
- `displayColumn` is a one-based visual cell column. Tabs advance to the next
  configured tab stop, full-width characters occupy two cells, and combining
  sequences are counted as one displayed character width.
- `utf16Offset` is the zero-based absolute index used by TextKit/`NSRange`.
- `selectedCharacterCount` counts user-perceived Swift `Character` values for
  display, while `selectedUTF16Length` preserves the TextKit unit count.
- `selectionRangeCount` distinguishes one selection from multiple ranges or
  carets.

Code must not pass `displayColumn` to TextKit or present `utf16Offset` as a
visual column. The status bar shows the display coordinate and exposes the
UTF-16 offset in its tooltip.

Encoding, byte-order mark, line ending, and language/FileType Profile are
clickable controls. Encoding uses the existing Reopen with Encoding workflow,
so unsaved-change protection remains intact. BOM choices are disabled when the
active encoding has no BOM convention. Changing BOM or line ending is a file
format edit: `Document.markFormatModified()` keeps the tab dirty until a
successful save even when the text itself has not changed. Language selection
is an editor interpretation override and does not modify file bytes.

The insert/overwrite indicator is intentionally absent because MaruEdit does
not currently implement overwrite mode. Showing a fixed “Insert” label would
claim a mode distinction that does not exist.
