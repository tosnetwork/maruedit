# MaruEdit 0.1.1

MaruEdit 0.1.1 expands the first public preview into a substantially more
complete AI-native, native macOS text editor for developer workflows.

## Highlights

- Introduces the Maru Classic workspace with compact tabs, a character ruler,
  a customizable command toolbar, status controls, and Files, Outline, and
  Results utility panes.
- Expands editing with multiple selections, BOX selection, insert/overwrite
  modes, CJK IME support, line markers, split views, document comparison,
  completion, folding, and outline navigation.
- Expands Find, Replace, folder Grep, Grep Replace, open-buffer search, result
  refinement, and structured-result export.
- Adds configurable key bindings, file-type profiles, JavaScript macros,
  external commands, templates, encoding preservation, recovery, and external
  file-change conflict handling.
- Adds Japanese and English interface resources and a bundled PDF manual.
- Refreshes the application icon with an original emerald M and AI-cursor mark
  on a deep blue-green background.
- Hardens release packaging, bundle validation, CI, security documentation, and
  reproducible release checks.

The download is a Universal application for Apple Silicon and Intel and
requires macOS 13 or later. Verify the DMG against the attached SHA-256 file
before installation.

## Unsigned preview

This build is not yet signed with a Developer ID Application certificate or
notarized by Apple. macOS may block its first launch. After copying MaruEdit to
Applications, Control-click it, choose **Open**, and confirm only if you trust
this repository. If it remains blocked, use **System Settings → Privacy &
Security → Open Anyway**. As a last resort, after verifying the attached
SHA-256 checksum, remove only MaruEdit's quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MaruEdit.app
```

A signed and notarized build is planned for a future release.

MaruEdit is an independent open-source project and is not affiliated with or
endorsed by any commercial editor vendor. See `NOTICE.md` and `UPSTREAM.md` for
license and provenance information.
