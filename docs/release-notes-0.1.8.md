# MaruEdit 0.1.8

MaruEdit 0.1.8 fixes the part of tab handling that got worse the more tabs you
had open: closing a group of tabs asked whether to save once *per tab*. Close
twelve tabs and you answered twelve dialogs. This release replaces that with a
single question for the whole batch, and adds explicit menu items for the two
answers people almost always want.

## Batch closing from the tab bar

Right-click anywhere on the tab bar — including the empty space past the last
tab — and the menu now ends its close section with three new items:

| Item | What it does |
| --- | --- |
| **Close All Tabs** | Closes every tab, asking once about unsaved work |
| **Save All and Close All Tabs** | Saves every modified document, then closes everything |
| **Close All Tabs Without Saving** | Discards every unsaved change, after one confirmation |

The existing per-tab items — Close Tab, Close Other Tabs, Close Tabs to the
Left, Close Tabs to the Right — are unchanged in what they close.

This follows the Maru workflow the editor takes its conventions from, which
keeps range closes on the tab itself and the save-everything variants on the
File menu. MaruEdit already had the File menu commands — **Save All and Close**
and **Discard All and Close** — but they were not reachable from the tab bar,
which is where you are when you decide to close tabs. See
`docs/maru-compatibility.md` for what compatibility does and does not mean.

## One question per batch, not per tab

Every multi-tab close now collects the unsaved documents first and asks once:

> **Save changes to 5 documents before closing?**
> These documents have unsaved changes:
> notes.md, draft.txt, config.json, log.txt, scratch.md
>
> [ Save All ] [ Don't Save ] [ Cancel ]

That applies to Close Other Tabs and the left/right range closes as well, not
only to the new Close All items. Details worth knowing:

- A batch containing only **one** unsaved document still shows the ordinary
  single-document prompt — a batch dialog listing one file would be noise.
- **Cancel** leaves everything open and unsaved. Nothing is closed before the
  question is answered.
- **Close All Tabs Without Saving** confirms once when the batch has unsaved
  changes, since a stray right-click should not be able to discard a day's
  work. Choosing "Don't Save" at the batch question does not confirm again —
  you already answered.
- The tab you right-clicked survives Close Other Tabs and the range closes, and
  is *not* saved along with the batch. It stays exactly as it was.
- Long batches list the first ten documents and summarize the rest, so the
  dialog's buttons stay on screen.

## Also fixed

Two problems found while testing the above, both of which affected existing
behaviour too:

- **Escape now cancels the close-confirmation alerts.** AppKit binds Escape
  only to a button literally titled "Cancel", so the localized button had no
  key equivalent and the alert could be dismissed only with the mouse. The
  single-document "Save changes to …?" alert had the same problem and is fixed
  as well.
- **The window title no longer names a closed document.** Closing tabs changed
  the current document without going through tab selection, so the title kept
  showing whatever was open before. It now follows the current tab, including
  when closing everything leaves an empty Untitled tab.

In the discard confirmation, Cancel is the default button: Return must not be
able to throw away every unsaved document.

## Compatibility

Nothing about file handling, encodings, or on-disk formats changed. The File
menu commands, the `window.closeOtherTabs` / `closeTabsLeft` / `closeTabsRight`
commands, and any key bindings assigned to them keep working; they simply ask
one question now instead of many.

The agent bridge version advances to 0.1.8 in step with the app, so a bridge
and an application from different builds are still detected as mismatched.

The download requires macOS 13 or later.

## Verifying and opening this build

This build is signed ad-hoc and is not notarized by Apple, so macOS cannot tell
you who built it. Two consequences follow, and they are separate:

**1. Check what you downloaded.** The published SHA-256 is what stands in for a
developer signature:

```bash
shasum -a 256 -c MaruEdit-0.1.8.dmg.sha256
```

Be clear about its limit: the DMG and the checksum come from the same GitHub
release, so this catches a corrupted or truncated download, not a compromised
release. If you need a stronger guarantee, rebuild from the tag —
`docs/reproducible-releases.md` gives the procedure, including why a rebuilt
binary's digest normally differs from the published one and what inputs have to
match before a comparison means anything.

**2. Let it open.** macOS quarantines anything downloaded from the internet and
will refuse to launch a build it cannot attest. After copying MaruEdit to
Applications, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MaruEdit.app
```

The `-r` is required: the bundle contains a second executable — the MCP bridge
— and a non-recursive removal leaves it quarantined, so the agent interface
would fail to start while the editor appeared to work.

Alternatively, launch it once, let macOS block it, then allow it under **System
Settings → Privacy & Security → Open Anyway**. Recent macOS versions no longer
offer the older Control-click → Open override for apps that fail notarization,
so that route may not appear.

`spctl --assess` reports `rejected` for this build either way, including after
the quarantine attribute is removed. That is the absence of notarization, not a
sign of a damaged download.

Run these commands only if you trust this repository. Removing quarantine
disables the only check macOS was performing, which is why the checksum step
comes first.

MaruEdit is an independent open-source project and is not affiliated with or
endorsed by any commercial editor vendor. See `NOTICE.md` and `UPSTREAM.md` for
license and provenance information.
