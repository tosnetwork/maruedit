# Changelog

All notable changes to MaruEdit are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) structure and uses
semantic version tags.

## [Unreleased]

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
