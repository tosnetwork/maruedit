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

## Repeatable UI-test launch

The Release app has a process-local test mode that neither restores nor saves
the user's Session file. It can seed deterministic content and selections:

```sh
MARUEDIT_UI_TEST_MODE=1 \
MARUEDIT_UI_TEST_CONTENT='aa aa' \
MARUEDIT_UI_TEST_SELECTIONS='0:2,3:2' \
./MaruEdit.app/Contents/MacOS/MaruEdit
```

This mode also rejects queued Finder open-file events, so GUI verification
does not request access to files from the user's previous session.

## 2026-08-04 verification record

- Environment: macOS 26.5.2 (25F84), arm64, local Release build from
  `codex/m3-grep-rescue`.
- Japanese Romaji (Kotoeri): candidate window followed the primary selection;
  Space candidate selection committed `日本語 日本語`; one Undo restored
  `aa aa`, and one Redo restored both commits. Two Escape presses during the
  active Romaji conversion restored `aa aa` without changing the secondary
  selection. Pass.
- Simplified Chinese Pinyin (SCIM ITABC): candidate UI appeared for
  `zhongwen`; Space committed `中文 中文`; Undo/Redo restored both states.
  Escape cancellation restored the seeded text after the deferred-cancel fix.
  Pass.
- Japanese direct Kana typing and non-first Kanji candidate: not executed on
  this machine because only the Romaji Kotoeri input mode is enabled. The M4
  Gate remains open until this final manual case is verified.

The run exposed three real system paths absent from the original deterministic
tests: legacy one-argument `insertText`, unmark-only commits, and cancellation
whose final TextKit mutation occurs after `cancelOperation`. All are now
covered by `CJKIMETests`.
