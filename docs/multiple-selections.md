# Multiple Selections

MaruEdit applies one multi-selection edit as one Undo transaction. Edits
are normalized and applied from the highest document offset to the lowest,
so earlier replacements cannot shift later targets.

## Clipboard behavior

When pasted text contains exactly one newline-separated fragment per
selection, fragment 1 replaces selection 1, fragment 2 replaces selection
2, and so on. Otherwise, the complete clipboard text replaces every
selection. A trailing newline therefore represents an additional empty
fragment.

Overlapping selections are merged before editing. The earliest normalized
selection supplies the replacement text for the merged range. Adjacent
selections remain independent.

TextKit 1 displays multiple non-empty ranges through `selectedRanges`, but
collapses multiple zero-length insertion points. MaruEdit therefore keeps
collapsed multi-cursors in the per-editor `SelectionSet`; editing, Undo,
Redo, and future caret drawing use that logical model.

## BOX selection

Option-drag creates a rectangular selection. The Edit menu also exposes
“Begin Column Selection” for keyboard and future command-palette use.
Columns are display cells: tabs advance to the configured tab stop,
full-width CJK and emoji occupy two cells, and combining marks stay with
their base character. Insertion beyond a short line pads it with spaces.

BOX selection is intentionally no-wrap in 1.0. The editor uses horizontal
scrolling while this model is active, so one logical line always represents
one rectangle row. This avoids ambiguous wrapped-row semantics.

For multiline paste, an exact fragment-to-row count maps one fragment to
each row. A single fragment repeats on every row. Any other line-count
mismatch repeats the complete clipboard text at every row; MaruEdit never
silently drops excess fragments.
