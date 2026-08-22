# MaruEdit 0.1.7

MaruEdit 0.1.7 corrects the documentation that shipped with 0.1.6. The
application itself is functionally identical — only its version strings differ.

If you already installed 0.1.6 and it is working, there is nothing here that
requires you to update.

## Why this release exists

0.1.6 introduced the agent automation interface, and its artifact was correct:
the published DMG contains both executables, universal, and verifies against
its own signature. What was wrong was the guidance around it, in ways that
would mislead anyone trying to check what they had downloaded.

- The reproducibility procedure told readers to verify the download with
  `spctl --assess` and `stapler validate`. Both fail by design on a build that
  was never notarized — `spctl` reports `rejected` even after the quarantine
  attribute is removed, since it judges policy rather than the attribute — so
  following the instructions produced what looked like evidence of a tampered
  download. `codesign --verify --deep --strict` does pass, and is what the
  procedure now recommends, with its actual meaning stated: it proves the
  bundle matches its own seal, and nothing about who built it.

- The same procedure compared only the application binary, leaving the MCP
  bridge — the executable that talks to external agents — unverified. Both are
  covered now.

- Its shell snippet assigned to `path`, which in zsh, macOS's default shell, is
  bound to `PATH`. Running the documented commands left the shell unable to
  find any command.

- It presented digest comparison as the main step with the caveat as a
  footnote, when a mismatch is the *expected* result across different
  toolchains. The caveat is now the guidance, and the inputs that must match
  before a comparison means anything are named.

- The tag itself named the wrong version to check out, which would have gone
  stale again every release. It takes the tag as a variable now.

## About 0.1.6

The agent automation interface — reading and editing open documents over the
Model Context Protocol, off by default, under grants a person approves and can
revoke — arrived in 0.1.6. See that release's notes for what it does and what
its trust model is and is not.

The download requires macOS 13 or later.

## Verifying and opening this build

This build is signed ad-hoc and is not notarized by Apple, so macOS cannot tell
you who built it. Two consequences follow, and they are separate:

**1. Check what you downloaded.** The published SHA-256 is what stands in for a
developer signature:

```bash
shasum -a 256 -c MaruEdit-0.1.7.dmg.sha256
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

The `-r` is required in this release. The bundle now contains a second
executable — the MCP bridge — and a non-recursive removal leaves it
quarantined, so the agent interface would fail to start while the editor
appeared to work.

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
