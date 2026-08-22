# Changelog

All notable changes to MaruEdit are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) structure and uses
semantic version tags.

## [Unreleased]

## [0.1.7] - 2026-08-23

### Fixed

- Corrected the release verification guidance, which told readers to check a
  download with `spctl --assess` and `stapler validate`. Both fail by design on
  an unnotarized build — `spctl` reports `rejected` regardless of the
  quarantine attribute — so following the documented steps looked like evidence
  of tampering. `codesign --verify --deep --strict` is recommended instead,
  with its actual guarantee stated.
- The reproducibility procedure now covers the MCP bridge as well as the
  application binary, takes the release tag as a variable rather than pinning
  one that goes stale, and no longer assigns to `path` — a variable bound to
  `PATH` in zsh, so running the documented commands left the shell unable to
  find any command.
- Digest comparison is presented as inconclusive across differing toolchains,
  which is the expected result, rather than as a pass/fail check with the
  caveat in a footnote.

The application is functionally unchanged from 0.1.6; only version strings
differ.

## [0.1.6] - 2026-08-23

### Added

- An automation interface that lets an external AI agent read and edit open
  documents over the Model Context Protocol, through a bridge shipped inside
  the app bundle. Off by default. Each agent configuration pairs once through a
  verification code, and every connection receives a grant frozen to the
  documents already open, separable by capability and revocable at any time.
- Optimistic concurrency on every write: an edit carries the revisions it was
  computed against, and one that is out of date is refused and told the current
  state instead of overwriting intervening work. One agent call is one undo
  entry.
- Regular-expression search in `search_documents`. Patterns whose shape permits
  exponential backtracking are refused with an explanation of how to rewrite
  them, since a started match has no cancellation point; what runs is bounded
  and the number of abandoned runs is capped.
- Explicit window targets for agent-invoked commands, so a person switching
  tabs mid-call cannot redirect one.

### Changed

- A document opened by an agent records the identity of the file it actually
  read, taken from the descriptor rather than by resolving the path a second
  time. An in-place save is refused if the file was replaced underneath.
- `ExternalChangeDetector` distinguishes "no baseline" from "unchanged". A file
  nobody has read is no longer reported as unmodified, which previously allowed
  a save to overwrite unseen content.
- Nested code in the app bundle is signed inside-out. The release build also
  ships the MCP bridge, which it previously omitted.

### Security

- An agent credential's public identifier is no longer its bearer secret, and
  the registry stores only a SHA-256 digest of the secret, compared in constant
  time. Previously the identifier was the secret and was stored in plain text
  as its own key, so anything that could read the registry held every
  credential. Credentials written under the previous scheme are discarded
  rather than migrated, and affected configurations pair again.
- The credential backend is chosen from the build's code identity: the Keychain
  where a stable Team Identifier makes its access control enforceable, a
  `0600` file otherwise. An ad-hoc-signed build cannot read back its own
  Keychain items after an update, so a Keychain-backed credential would break
  on every release. Pairing states which backend was used.

### Release engineering

- Moved the release workflow off the deprecated Node 20 action runtime:
  `actions/checkout` now matches CI at v7, and `softprops/action-gh-release`
  moves to v3, whose only change from v2 is the Node 24 runtime.

## [0.1.5] - 2026-08-22

### Changed

- Made the active tab obvious in tab mode, following the emphasis options
  Hidemaru offers for its tab bar: the selected tab now gets its own face
  color (the editor surface), an accent line along its outer edge, a bold
  full-contrast label, and full row height, while unselected tabs sit
  recessed with a dimmed label and a visible divider. The rule separating
  the bar from the document breaks under the active tab so it reads as one
  surface with the text area, in both top and bottom bar positions. The
  accent line and the active face color can each be turned off from the tab
  bar context menu.

## [0.1.4] - 2026-08-08

### Fixed

- Fixed the placeholder name shown for a brand-new, never-saved document:
  the tab label, the classic heading, the window title, and related dialogs
  now correctly show the localized untitled placeholder (e.g. 無題 when the
  app language is set to Japanese) instead of always showing the English
  "Untitled" text regardless of language.

## [0.1.3] - 2026-08-08

### Added

- Added a Hidemaru-style current-line highlight that shades the full width of
  the line holding the caret (or each caret, in multi-cursor mode) so the
  editing position stays visible without a selection. Added a matching
  `View > Highlight Current Line` command and Settings checkbox; on by default,
  toggleable, and included in preferences export/import.

### Fixed

- Padded the application icon artwork within its 1024×1024 canvas to match
  macOS's icon-content convention (previously the artwork bled to the edge),
  so MaruEdit no longer renders oversized next to other apps in the Dock and
  the Cmd+Tab application switcher.

## [0.1.2] - 2026-08-06

### Changed

- Refined the MaruEdit application icon with an original upright, flowing M,
  variable stroke weight, softer continuous curves, and a more prominent
  AI-cursor dot while retaining the deep blue-green and emerald palette.

## [0.1.1] - 2026-08-06

### Added

- Expanded Maru-style tab behavior with top/bottom placement, optional
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
- Expanded the opt-in clean-room Maru macro translator with typed variables,
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
  its Maru-style command toolbar is visible by default; Modern remains selectable.
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
