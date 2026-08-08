# MaruEdit 0.1.3

MaruEdit 0.1.3 is a focused usability release for the native macOS editor.

## Highlights

- Adds a Hidemaru-style current-line highlight: the full width of the line
  holding the caret is shaded so the editing position stays visible even
  without a selection, including in multi-cursor mode. On by default, with a
  new `View > Highlight Current Line` command and Settings checkbox.
- Fixes an oversized application icon: the artwork previously bled to the
  edge of its canvas, making MaruEdit look noticeably larger than sibling
  apps in the Dock and the Cmd+Tab application switcher. The icon now follows
  macOS's standard content padding.

The download requires macOS 13 or later. Verify the DMG against the attached
SHA-256 file before installation.

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

MaruEdit is an independent open-source project and is not affiliated with or
endorsed by any commercial editor vendor. See `NOTICE.md` and `UPSTREAM.md` for
license and provenance information.
