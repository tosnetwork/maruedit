# TextKit 2 Spike

The experiment lives in the isolated `MaruEditTextKit2Spike` SwiftPM target.
Neither `MaruEditApp` nor `MaruEditCore` depends on it, so experiments cannot
silently change the production editor.

Environment: Apple M2 MacBook Air, macOS 26.5.2, Swift Debug build,
2026-08-05. The deterministic layout fixture is approximately 1 MiB and 38,000
lines. One diagnostic run measured TextKit 1 at 0.308 s and TextKit 2 at
0.521 s for full layout. These single Debug samples guide the migration
decision but are not release performance promises.

| Area | Probe result | Migration work / defect risk |
|---|---|---|
| Multiple selections | `NSTextView.selectedRanges` preserves two ranges | MaruEdit's `SelectionSet`, primary-range ordering, batch edits, and single-Undo behavior still need the full M4 suite ported. |
| BOX selection | No native replacement for MaruEdit's virtual-space and display-column model was found | Rebuild geometry mapping over `NSTextLayoutFragment` and repeat CJK/tab/short-line tests. Current model uses UTF-16 ranges independently of layout. |
| IME | The TextKit 2 view exposes the `NSTextInputClient` marked-text contract | This does not prove Japanese/Chinese IME correctness. MaruEdit's snapshot/reconcile logic is tied to current `NSTextStorage` callbacks; real IME sessions and M4 tests must pass before migration. |
| Layout | The isolated content storage/layout manager produces 38,000 fragments | The 1 MiB probe was about 1.7× slower than TextKit 1 in this run; no performance win is demonstrated. |
| Line numbers | TextKit 2 exposes layout fragments, not the glyph/line-fragment API used by `LineNumberView` | Rewrite visible-line enumeration, wrapped-line filtering, active-line state, and bookmark anchors. |
| Syntax/attributes | `NSTextContentStorage` provides backing `NSTextStorage` in the spike | Revision cancellation and bounded attribute application need port-specific validation. |

The spike deliberately does not implement a second production editor. A
half-ported editor would duplicate selection, IME, gutter, and highlighting
logic and create two behavioral sources of truth.

## Migration estimate and exit criteria

A future 2.0 investigation should budget separate work for the editor host,
layout/gutter, BOX geometry, IME reconciliation, highlighting integration, and
performance/visual regression. Migration is allowed only after:

- the entire selection, BOX, IME, line-editing, accessibility, and syntax suites
  run against a TextKit 2 adapter;
- real Japanese and Simplified Chinese IME sessions pass;
- 1 MiB and 10 MiB Release measurements are no worse than the TextKit 1
  baseline;
- line numbers, bookmarks, wrapping, and scrolling match screenshots; and
- the adapter replaces rather than duplicates production ownership.

See ADR-010 for the 1.0 decision.
