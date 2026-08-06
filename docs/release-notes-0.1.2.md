# MaruEdit 0.1.2

MaruEdit 0.1.2 is a visual refinement release for the native macOS editor.

## Highlights

- Introduces a redesigned, original MaruEdit application icon.
- Uses an upright, flowing M with gradual thick-to-thin strokes and softly
  rounded transitions for improved clarity at both Finder and Dock sizes.
- Enlarges the near-white AI-cursor dot to better balance the M and reinforce
  MaruEdit's AI-native identity.
- Retains the deep blue-green background, emerald foreground, transparent
  macOS icon corners, and Universal Apple Silicon/Intel packaging.

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
