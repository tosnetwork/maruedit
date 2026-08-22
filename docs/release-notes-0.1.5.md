# MaruEdit 0.1.5

MaruEdit 0.1.5 is a focused usability release for the native macOS editor.

## Highlights

- Makes the active tab obvious in tab mode. Previously the tab you were
  editing in was told apart only by a slightly heavier label, which was easy
  to miss. The selected tab now carries the editor's own face color, an accent
  line along its outer edge, a bold full-contrast label, and the full height of
  the tab row, while unselected tabs sit recessed with a dimmed label and a
  visible divider. The rule that separates the tab row from the text area
  breaks underneath the active tab, so the tab and the document read as one
  surface — in both the top and the bottom tab-bar positions.
- Adds two emphasis switches to the tab-row context menu, following the tab
  design options Hidemaru offers: **Line on Active Tab** (アクティブなタブに線)
  and **Color the Active Tab** (アクティブなタブの面に色). Both are on by
  default and can be turned off independently for a plainer row.

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
