# MaruEdit 0.1.0

MaruEdit 0.1.0 is the first public preview of an independent, native macOS
text editor built for modern developer workflows.

Highlights include encoding, BOM, and newline preservation; literal and regex
Find/Replace; folder Grep and previewed Grep Replace; BOX and multiple
selections; CJK IME support; configurable ordinary and chorded keys; file-type
profiles; JavaScript macros; external commands; crash recovery; and external
change conflict handling.

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
