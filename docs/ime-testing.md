# CJK IME Manual Test Checklist

Run this checklist on a signed or local Release build after any change to
`MaruTextView`, `SelectionSet`, keyboard routing, or multi-edit Undo.

For every case, create at least two selections. Confirm that the candidate
window follows the primary selection, marked text appears only there, the
final committed text is copied to every selection, Escape leaves secondary
selections unchanged, and one Undo reverses the complete commit.

## Japanese — Romaji

- Select two occurrences and compose `nihongo` → `日本語`.
- Move through candidates with Space before committing.
- Cancel an active composition with Escape.
- Commit, then Undo and Redo once each.

## Japanese — Kana

- Compose a hiragana word directly with Kana input.
- Convert it to kanji and choose a non-first candidate.
- Cancel an active composition with Escape.
- Commit, then Undo and Redo once each.

## Simplified Chinese — Pinyin

- Compose `zhongwen` → `中文` at multiple selections.
- Page through candidates before committing.
- Cancel an active composition with Escape.
- Commit, then Undo and Redo once each.

Record macOS version, input-source version, hardware architecture, build
configuration, commit SHA, and pass/fail notes with the release checklist.
