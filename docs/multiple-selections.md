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
