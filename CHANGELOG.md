# Changelog

All notable changes to MaruEdit are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) structure and uses
semantic version tags.

## [Unreleased]

### Added

- Expanded Hidemaru-style tab behavior with top/bottom placement, optional
  single-tab hiding, adaptive widths, drag reordering, and middle-click close;
  upgraded the character ruler with per-column ticks and a live column marker.
- Rebuilt Maru Classic around a compact in-window command bar above the tab row,
  with twenty-one grouped file/edit/search/navigation controls, persistent right-click
  customization, semantic color-coded icons, hover feedback, and no oversized
  macOS titlebar toolbar.
- Added native Page Setup and Print commands, presentation-only CSV/TSV table
  alignment, and non-destructive editing isolation for the current outline region.
- Added executable vertical TextKit layout feasibility coverage and a bounded-memory
  streaming edit/binary-row architecture for future huge-file and hex interfaces.
- Added per-document insert/overwrite modes with an explicit INS/OVR status,
  grapheme-safe replacement, IME and multiple-selection support, and a stable
  `edit.toggleInputMode` command.
- Added registry-backed word and paragraph movement, forward/backward word
  deletion, and multiple-selection-aware Title Case conversion.
- Added document-owned red/yellow/blue/green line markers with gutter colors,
  edit/Undo-stable anchors, wrapped navigation, and a Results-pane marker list.
- Added horizontal and vertical views of one document with independent selections,
  explicit close-split behavior, and optional bidirectional linked scrolling.
- Added two-document line diff with wrapped difference navigation and an undo-safe
  action for accepting the current hunk from the read-only right pane.
- Added bounded, project-contained ctags navigation with prompt and cursor-word
  jumps plus a LIFO return stack.
- Added bounded current-document and UTF-8 user-dictionary word completion with
  profile-controlled ranking, manual/automatic list, tooltip or status display,
  and per-profile macOS spelling and correction controls.
- Added expandable multiline Find/Replace fields and resizable multiline Grep
  fields, transient search-result gutter markers, and a bounded Results list.
- Added background Grep over the current unsaved buffer or every open buffer,
  Grep-over-results refinement, and export of structured results to a new document.
- Expanded File Type Profiles to schema 4 with per-profile fonts/colors, folding,
  templates, ordered encoding candidates, read-only load policy, save transforms,
  and bounded fail-closed backups; added New from Template to the File menu.
- Added Basic/Advanced Settings filtering and guarded per-section import/export.
- Expanded the opt-in clean-room Hidemaru macro translator with typed variables,
  guarded expressions, branches, cancellable loops, functions/subroutines, and
  portable Command Registry statements. Unsafe and Windows-only operations now
  receive distinct diagnostics, backed by a CC0 executable corpus and report.
- Added a Foundation-only incremental document-outline model with built-in
  symbol rules for source, markup, scripting, configuration, and SQL languages,
  plus bounded user-defined regex rules in versioned FileType Profiles. The
  Outline utility pane follows the active document and cursor and navigates to
  symbols without changing document content.
- Added a UI-independent folding model that derives nested fold regions from
  document outlines and preserves collapsed regions when surrounding lines move,
  with clickable gutter markers, registry-backed fold commands, TextKit layout,
  and per-file session restoration.
- Hardened user outline rules against malformed patterns, nested-quantifier
  backtracking, backreferences, oversized patterns/lines, and unbounded symbol output.
- Added the Maru Classic workspace foundation: a Classic Light palette, compact tabs,
  current-document heading and character ruler, favorite-command strip, explicit
  insert-mode status, a customizable command-registry toolbar, and Files / Outline /
  Results utility-pane switching. Heading, character ruler, and favorite-command
  strip visibility can be configured independently and updates immediately.

### Changed

- Existing pre-schema-5 settings now migrate to the Maru Classic workspace so
  its Hidemaru-style command toolbar is visible by default; Modern remains selectable.
- Maru Classic is now the new-user default, while existing settings migrate to the
  Maru Classic workspace without changing documents or overriding their saved theme.

### Documentation

- Added the 1.0 user, Search/Grep, migration, compatibility, FAQ, and troubleshooting guides; linked the existing key-binding, macro, and external-command references from the README.
- Replaced stale sub-megabyte/20 MB and unsigned-download claims with reproducible M7 measurements and a Gatekeeper-safe release policy.

### Security

- Added the vulnerability-reporting policy, Macro/Process threat model, reproducible-release procedure, and a CI-enforced dependency/certificate/secret audit.

### Release engineering

- Added a fail-closed Developer ID, Hardened Runtime, notarization, stapling, Gatekeeper, DMG, and SHA-256 pipeline plus drafted 1.0 release notes.
- Added naming/trademark search evidence and rollback/hotfix procedures; release DMGs include license, notice, and upstream-attribution files.

### Changed

- Entered the 1.0 feature freeze; changes are now limited to release work and
  defect, security, accessibility, localization, test, and documentation fixes.

### Known limitations

- Cold launch, one-window idle RSS, and 1 MB open time do not yet meet their
  engineering targets. See GitHub issues #1–#3 and `docs/performance.md`.
