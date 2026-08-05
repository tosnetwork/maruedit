# Maru Classic Implementation Roadmap

This roadmap turns the product-gap audit into testable work. “Complete” means
portable, publicly documented Hidemaru workflows on macOS; it excludes copied
assets/code, Windows registry/DLL/tray integration, and implicit capabilities
that would weaken MaruEdit's security model.

## MC1 — Workspace foundation

- [x] Versioned `WorkspaceStyle` preference with schema migration.
- [x] Maru Classic is the new-user default; Maru Modern remains selectable.
- [x] Immediate Settings switch without document mutation.
- [x] Current-document heading bar.
- [x] Character-column ruler foundation.
- [x] Compact Classic tab presentation.
- [x] Favorite/function command strip foundation.
- [x] Explicit insert-mode status segment.
- [x] Original Classic Light palette with live switching.
- [x] Native customizable toolbar backed by Command Registry IDs.
- [x] Files / Outline / Results pane switcher and single-file closed default.
- [x] User-configurable visibility for heading, ruler and command strip.
- [ ] Real VoiceOver and visible screenshot verification.

## MC2 — Outline and folding

- [x] Pure incremental outline model and per-language symbol rules.
- [x] User-defined regex outline rules in FileType Profiles.
- [x] Outline pane and current-heading synchronization.
- [x] Fold gutter, fold commands and persisted fold state.
- [x] Large-file and malformed-rule degradation tests.

## MC3 — Editing parity

- [x] Insert/overwrite editing modes with a visible status segment.
- [x] IME, grapheme, BOX, multiple-selection and single-undo coverage.
- [x] Richer word/paragraph movement, deletion and conversion commands.
- [x] Color markers, marker navigation and marker list.

## MC4 — Split, compare and navigation

- [x] Horizontal/vertical editor split and independent selections.
- [x] Optional linked scrolling.
- [x] Native text diff, next/previous difference and merge-safe actions.
- [x] Tag jump, direct tag jump and back-tag stack.

## MC5 — Completion and spelling

- [x] Current-document word completion.
- [x] User dictionaries and per-profile completion sources/ranking.
- [x] Manual/automatic list, tooltip and status presentation.
- [x] Per-profile macOS spell checking and corrections.

## MC6 — Search/Grep parity

- [x] Resizable multiline Find/Replace/Grep fields.
- [x] Search color markers and marker-list results.
- [x] Grep current unsaved document and all open documents.
- [x] Output results as a document and refine Grep results.

## MC7 — File-type and settings depth

- [x] Profile font/colors, spelling, completion, outline and folding.
- [x] Templates, backups, load/save policies and encoding candidate order.
- [x] Searchable Basic/Advanced settings with per-section reset/import/export.

## MC8 — Macro compatibility

- [x] Build a legally redistributable macro behavior corpus.
- [x] Variables, expressions, branching, loops, functions and subroutines.
- [x] Portable editor/search/window/outline statements.
- [x] Explicit diagnostics for unsafe or Windows-only statements.
- [x] Compatibility report generated from executable tests.

## MC9 — Specialist workflows

- [ ] Native print and page setup.
- [ ] CSV/TSV table mode.
- [ ] Partial editing of an outline region.
- [ ] Vertical writing/column-layout feasibility spike.
- [ ] Streaming editable huge-file and binary-view architecture.

## MC10 — Adoption gate

- [ ] Every portable public behavior in the gap matrix is supported or has a
  documented macOS-native equivalent.
- [ ] Five experienced Hidemaru users complete the scripted migration study.
- [ ] English/Japanese/Simplified Chinese, IME and VoiceOver manual matrix.
- [ ] Fresh screenshots and guides contain no stale LiteEdit branding.
- [ ] Signed/notarized Universal build passes Gatekeeper on a clean Mac.
