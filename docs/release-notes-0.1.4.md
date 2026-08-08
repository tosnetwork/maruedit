# MaruEdit 0.1.4

MaruEdit 0.1.4 is a focused localization fix for the native macOS editor.

## Highlights

- Fixes the placeholder name shown for a brand-new, never-saved document: the
  tab label, the classic heading, the window title, and related dialogs now
  correctly show the localized untitled placeholder (e.g. 無題 when the app
  language is set to Japanese) instead of always showing the English
  "Untitled" text regardless of the selected language.

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
