# Changelog

All notable changes to MaruEdit are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) structure and uses
semantic version tags.

## [Unreleased]

### Added

- Added a Foundation-only incremental document-outline model with built-in
  symbol rules for source, markup, scripting, configuration, and SQL languages,
  plus bounded user-defined regex rules in versioned FileType Profiles. The
  Outline utility pane follows the active document and cursor and navigates to
  symbols without changing document content.
- Added a UI-independent folding model that derives nested fold regions from
  document outlines and preserves collapsed regions when surrounding lines move,
  with clickable gutter markers, registry-backed fold commands, TextKit layout,
  and per-file session restoration.
- Added the Maru Classic workspace foundation: a Classic Light palette, compact tabs,
  current-document heading and character ruler, favorite-command strip, explicit
  insert-mode status, a customizable command-registry toolbar, and Files / Outline /
  Results utility-pane switching. Heading, character ruler, and favorite-command
  strip visibility can be configured independently and updates immediately.

### Changed

- Maru Classic is now the new-user default, while existing settings migrate to the
  Maru Modern workspace without changing documents or overriding their saved theme.

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
